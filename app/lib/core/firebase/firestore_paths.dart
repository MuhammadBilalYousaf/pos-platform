/// Firestore layout for the multi-tenant POS (all store data under [businesses]).
class FirestorePaths {
  static const users = 'users';
  static const businesses = 'businesses';
  static const platform = 'platform';
  static const platformAudit = 'platform_audit';
  static const ownerUnlocks = 'owner_unlocks';

  static String business(String businessId) => '$businesses/$businessId';

  // --- Per-business subcollections (businesses/{businessId}/...) ---
  static String branches(String businessId) => '${business(businessId)}/branches';
  static String categories(String businessId) => '${business(businessId)}/categories';
  static String products(String businessId) => '${business(businessId)}/products';
  static String ingredients(String businessId) => '${business(businessId)}/ingredients';
  static String units(String businessId) => '${business(businessId)}/units';
  static String discounts(String businessId) => '${business(businessId)}/discounts';
  static String recipes(String businessId) => '${business(businessId)}/recipes';
  static String inventory(String businessId) => '${business(businessId)}/inventory';
  static String inventoryTransactions(String businessId) => '${business(businessId)}/inventory_transactions';
  static String orders(String businessId) => '${business(businessId)}/orders';
  static String heldTickets(String businessId) => '${business(businessId)}/held_tickets';
  static String customers(String businessId) => '${business(businessId)}/customers';
  static String suppliers(String businessId) => '${business(businessId)}/suppliers';
  static String purchases(String businessId) => '${business(businessId)}/purchases';
  static String stockTransfers(String businessId) => '${business(businessId)}/stock_transfers';
  static String waste(String businessId) => '${business(businessId)}/waste';
  static String auditLogs(String businessId) => '${business(businessId)}/audit_logs';
}
