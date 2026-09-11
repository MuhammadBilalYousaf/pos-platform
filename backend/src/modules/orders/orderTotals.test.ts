import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateOrderTotals } from './orderTotals';

test('calculates line totals, order discount, and tax with decimal money', () => {
  const result = calculateOrderTotals({
    taxRate: '0.0500',
    orderDiscountAmount: '20',
    lines: [
      { quantity: 2, unitPrice: '250.00', extraPrice: '50.00' },
      { quantity: 1, unitPrice: '80.00', discountAmount: '10' },
    ],
  });

  assert.equal(result.lineTotals[0], '600.00');
  assert.equal(result.lineTotals[1], '70.00');
  assert.equal(result.subtotal, '670.00');
  assert.equal(result.discountAmount, '20.00');
  assert.equal(result.taxAmount, '32.50');
  assert.equal(result.total, '682.50');
});

test('never returns a negative line total', () => {
  const result = calculateOrderTotals({
    taxRate: 0,
    lines: [{ quantity: 1, unitPrice: '50', discountAmount: '80' }],
  });
  assert.equal(result.lineTotals[0], '0.00');
  assert.equal(result.total, '0.00');
});
