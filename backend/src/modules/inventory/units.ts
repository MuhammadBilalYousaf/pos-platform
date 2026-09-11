import { Decimal } from 'decimal.js';
import { AppError } from '../../utils/appError';

export function toBaseQuantity(quantity: string | number, conversionToBase: string | number): Decimal {
  const qty = new Decimal(quantity);
  const factor = new Decimal(conversionToBase);
  if (qty.lte(0) || factor.lte(0)) {
    throw new AppError(400, 'INVALID_QUANTITY', 'Quantity must be greater than zero.');
  }
  return qty.times(factor);
}

export function fromBaseQuantity(quantityBase: string | number, conversionToBase: string | number): Decimal {
  return new Decimal(quantityBase).div(new Decimal(conversionToBase));
}
