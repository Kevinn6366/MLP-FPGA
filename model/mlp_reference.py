"""Reproducible untrained integer MLP and independent simulation oracle.

No dependencies. Random generation is explicit (generate); run(check) never
silently replaces weights. Tensor storage is row-major, batch size one.
"""
from pathlib import Path
import argparse
import itertools
import json
import random

ROOT = Path(__file__).resolve().parents[1]
SHAPE = [4, 8, 8, 8, 2]
SEED = 20261010


def validate(model):
    assert model['shape'] == SHAPE
    assert len(model['layers']) == 4
    bound = 128
    bounds = []
    for i, layer in enumerate(model['layers']):
        assert len(layer['weights']) == SHAPE[i+1]
        assert len(layer['biases']) == SHAPE[i+1]
        for row in layer['weights']:
            assert len(row) == SHAPE[i]
            assert all(type(w) is int and -3 <= w <= 3 for w in row)
        assert all(type(b) is int and -8 <= b <= 8 for b in layer['biases'])
        bound = SHAPE[i] * bound * 3 + 8
        assert bound < 2**31
        bounds.append(bound)
    return bounds


def reference(x, model):
    assert len(x) == 4 and all(type(v) is int and -128 <= v <= 127 for v in x)
    value = list(x)
    activations, preactivations = [], []
    for i, layer in enumerate(model['layers']):
        # Python integer arithmetic has no fixed-width overflow.
        raw = [b + sum(a*w for a, w in zip(value, row))
               for row, b in zip(layer['weights'], layer['biases'])]
        assert all(-(2**31) <= v < 2**31 for v in raw)
        value = [max(0, v) for v in raw] if i < 3 else raw
        preactivations.extend(raw)
        activations.extend(value)
    return value, activations, preactivations


def float_reference(x, model):
    value = list(map(float, x))
    for i, layer in enumerate(model['layers']):
        value = [float(b) + sum(a*float(w) for a, w in zip(value, row))
                 for row, b in zip(layer['weights'], layer['biases'])]
        if i < 3:
            value = [max(0.0, v) for v in value]
    return value


def packed(values, bits):
    return sum((v & ((1 << bits)-1)) << (bits*i) for i, v in enumerate(values))


def artifacts(model):
    bounds = validate(model)
    weights = [w for layer in model['layers'] for row in layer['weights'] for w in row]
    biases = [b for layer in model['layers'] for b in layer['biases']]
    lines = ['// Generated from model/mlp4_weights.json; do not edit by hand.']
    for name, values, aw, width in [('weight', weights, 8, 8), ('bias', biases, 5, 16)]:
        lines += [f'function signed [{width-1}:0] {name}_rom;',
                  f'    input [{aw-1}:0] address;', '    begin', '        case (address)']
        for i, v in enumerate(values):
            literal = f"{width}'sd{abs(v)}"
            if v < 0:
                literal = '-' + literal
            lines.append(f"            {aw}'d{i}: {name}_rom = {literal};")
        lines += [f"            default: {name}_rom = {width}'sd0;", '        endcase', '    end', 'endfunction']
    rom = '\n'.join(lines)+'\n'
    cases = [[1,2,3,4], [0]*4, [-128]*4, [127]*4, [-128,127,-128,127]]
    cases += [list(x) for x in itertools.product([-128,127], repeat=4)]
    cases += [[sign if i == j else 0 for i in range(4)] for j in range(4) for sign in [-1,1]]
    rng = random.Random(SEED + 1)
    cases += [[rng.randint(-128,127) for _ in range(4)] for _ in range(64)]
    vectors = [f'// {len(cases)} cases; each includes all 26 neuron outputs and preactivations.']
    outputs, hidden_negative, hidden_positive = [], 0, 0
    records = []
    for x in cases:
        y, acts, raw = reference(x, model)
        assert list(map(float, y)) == float_reference(x, model)
        hidden_negative += sum(v < 0 for v in raw[:24])
        hidden_positive += sum(v > 0 for v in raw[:24])
        outputs.extend(y)
        vectors.append(f"run_case(32'h{packed(x,8):08x}, 832'h{packed(acts,32):0208x}, 832'h{packed(raw,32):0208x});")
        records.append(dict(input=x, output=y, layer_outputs=[acts[:8], acts[8:16], acts[16:24], acts[24:]]))
    assert hidden_negative and hidden_positive
    assert min(outputs) < 0 < max(outputs), 'Exercise signed final outputs'
    summary = dict(seed=SEED, shape=SHAPE, weight_count=len(weights), bias_count=len(biases),
                   bounds=bounds, cases=len(cases), latency_cycles=229,
                   hidden_negative_checks=hidden_negative, hidden_positive_checks=hidden_positive,
                   output_range=[min(outputs),max(outputs)], example=records[0])
    return {'rtl/mlp4_weights.vh':rom, 'sim/mlp4_vectors.vh':'\n'.join(vectors)+'\n',
            'model/mlp4_reference_summary.json':json.dumps(summary,indent=2)+'\n'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['generate','check'])
    args = parser.parse_args()
    path = ROOT/'model/mlp4_weights.json'
    if args.action == 'generate':
        rng = random.Random(SEED)
        model = dict(seed=SEED, shape=SHAPE, layers=[])
        for ni,no in zip(SHAPE, SHAPE[1:]):
            model['layers'].append(dict(weights=[[rng.randint(-3,3) for _ in range(ni)] for _ in range(no)],
                                        biases=[rng.randint(-8,8) for _ in range(no)]))
        path.write_text(json.dumps(model,indent=2)+'\n', encoding='ascii')
    model = json.loads(path.read_text(encoding='ascii'))
    result = artifacts(model)
    for rel, content in result.items():
        target = ROOT/rel
        if args.action == 'generate':
            target.write_text(content,encoding='ascii')
        else:
            assert target.read_text(encoding='ascii') == content, f'Stale artifact: {rel}'
    print(result['model/mlp4_reference_summary.json'])
    print('REFERENCE_PASS: integer/float agreement, full-domain bounds, generated ROM and vectors consistent')


if __name__ == '__main__':
    main()
