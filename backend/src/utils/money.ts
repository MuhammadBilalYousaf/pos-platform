import { Decimal } from 'decimal.js';

Decimal.set({ precision: 20, rounding: Decimal.ROUND_HALF_UP });

export type Money = Decimal;

export function money(value: string | number | Decimal): Decimal {
  return new Decimal(value);
}

export function moneyString(value: string | number | Decimal): string {
  return money(value).toFixed(2);
}

export function qtyString(value: string | number | Decimal, places = 4): string {
  return new Decimal(value).toFixed(places);
}

export function sumMoney(values: Array<string | number | Decimal>): Decimal {
  return values.reduce<Decimal>((total, value) => total.plus(money(value)), money(0));
}
