import { query } from '../../database/pool';
import { AppError } from '../../utils/appError';

export async function assertBranchOfBusiness(businessId: string, branchId: string): Promise<void> {
  const rows = await query<{ id: string }>(
    'SELECT id FROM branches WHERE id = ? AND business_id = ? LIMIT 1',
    [branchId, businessId],
  );
  if (!rows[0]) {
    throw new AppError(404, 'BRANCH_NOT_FOUND', 'Branch was not found for this business.');
  }
}

export async function getBusinessTaxRate(businessId: string): Promise<string> {
  const rows = await query<{ tax_rate: string }>(
    'SELECT tax_rate FROM businesses WHERE id = ? LIMIT 1',
    [businessId],
  );
  if (!rows[0]) {
    throw new AppError(404, 'BUSINESS_NOT_FOUND', 'Business was not found.');
  }
  return String(rows[0].tax_rate);
}
