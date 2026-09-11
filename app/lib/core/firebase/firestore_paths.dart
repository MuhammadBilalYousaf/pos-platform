class FirestorePaths {
  static const users = 'users';
  static const businesses = 'businesses';

  static String business(String businessId) => '$businesses/$businessId';

  static String branches(String businessId) => '${business(businessId)}/branches';
  static String categories(String businessId) => '${business(businessId)}/categories';
  static String products(String businessId) => '${business(businessId)}/products';
  static String ingredients(String businessId) => '${business(businessId)}/ingredients';
  static String recipes(String businessId) => '${business(businessId)}/recipes';
  static String inventory(String businessId) => '${business(businessId)}/inventory';
  static String inventoryTransactions(String businessId) => '${business(businessId)}/inventory_transactions';
  static String orders(String businessId) => '${business(businessId)}/orders';
  static String customers(String businessId) => '${business(businessId)}/customers';
}
