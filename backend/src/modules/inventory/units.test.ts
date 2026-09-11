import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toBaseQuantity } from './units';

test('converts kilograms to grams', () => {
  assert.equal(toBaseQuantity(10, 1000).toFixed(0), '10000');
});

test('converts liters to milliliters', () => {
  assert.equal(toBaseQuantity('1.5', '1000').toFixed(0), '1500');
});
