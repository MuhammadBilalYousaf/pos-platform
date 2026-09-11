import { Decimal } from 'decimal.js';
import { money, moneyString } from '../../utils/money';

export interface OrderLineInput {
  quantity: string | number;
  unitPrice: string | number;
  extraPrice?: string | number;
  discountAmount?: string | number;
}

export interface OrderTotalsInput {
  lines: OrderLineInput[];
  orderDiscountAmount?: string | number;
  taxRate: string | number;
}

export interface OrderTotals {
  subtotal: string;
  discountAmount: string;
  taxAmount: string;
  total: string;
  lineTotals: string[];
}

export function calculateOrderTotals(input: OrderTotalsInput): OrderTotals {
  const lineTotals = input.lines.map((line) => {
    const qty = money(line.quantity);
    if (qty.lte(0)) {
      throw new Error('INVALID_QUANTITY');
    }
    const unit = money(line.unitPrice).plus(money(line.extraPrice ?? 0));
    const raw = unit.times(qty);
    const discount = money(line.discountAmount ?? 0);
    const lineTotal = Decimal.max(raw.minus(discount), money(0));
    return lineTotal;
  });

  const subtotal = lineTotals.reduce((sum, value) => sum.plus(value), money(0));
  const discountAmount = Decimal.min(money(input.orderDiscountAmount ?? 0), subtotal);
  const taxable = subtotal.minus(discountAmount);
  const taxAmount = taxable.times(money(input.taxRate));
  const total = taxable.plus(taxAmount);

  return {
    subtotal: moneyString(subtotal),
    discountAmount: moneyString(discountAmount),
    taxAmount: moneyString(taxAmount),
    total: moneyString(total),
    lineTotals: lineTotals.map((value) => moneyString(value)),
  };
}
