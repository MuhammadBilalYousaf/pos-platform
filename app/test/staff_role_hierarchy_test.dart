import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/auth/domain/permissions.dart';

void main() {
  group('PosRole staff hierarchy', () {
    test('manager can only view and edit cashiers', () {
      expect(PosRole.canViewStaffRole(PosRole.branchManager, PosRole.cashier), isTrue);
      expect(PosRole.canEditStaffRole(PosRole.branchManager, PosRole.cashier), isTrue);

      expect(PosRole.canViewStaffRole(PosRole.branchManager, PosRole.branchManager), isFalse);
      expect(PosRole.canViewStaffRole(PosRole.branchManager, PosRole.businessAdmin), isFalse);
      expect(PosRole.canViewStaffRole(PosRole.branchManager, PosRole.platformSuperAdmin), isFalse);

      expect(PosRole.canEditStaffRole(PosRole.branchManager, PosRole.businessAdmin), isFalse);
      expect(PosRole.canAssignRole(PosRole.branchManager, PosRole.businessAdmin), isFalse);
      expect(PosRole.canAssignRole(PosRole.branchManager, PosRole.branchManager), isFalse);
      expect(PosRole.canAssignRole(PosRole.branchManager, PosRole.cashier), isTrue);
    });

    test('business admin can manage admins, managers, and cashiers', () {
      expect(PosRole.canViewStaffRole(PosRole.businessAdmin, PosRole.businessAdmin), isTrue);
      expect(PosRole.canViewStaffRole(PosRole.businessAdmin, PosRole.branchManager), isTrue);
      expect(PosRole.canViewStaffRole(PosRole.businessAdmin, PosRole.cashier), isTrue);
      expect(PosRole.canViewStaffRole(PosRole.businessAdmin, PosRole.platformSuperAdmin), isFalse);

      expect(PosRole.canAssignRole(PosRole.businessAdmin, PosRole.businessAdmin), isTrue);
      expect(PosRole.canAssignRole(PosRole.businessAdmin, PosRole.branchManager), isTrue);
      expect(PosRole.canAssignRole(PosRole.businessAdmin, PosRole.cashier), isTrue);
    });

    test('rank order is super admin > business admin > manager > cashier', () {
      expect(PosRole.rank(PosRole.platformSuperAdmin), greaterThan(PosRole.rank(PosRole.businessAdmin)));
      expect(PosRole.rank(PosRole.businessAdmin), greaterThan(PosRole.rank(PosRole.branchManager)));
      expect(PosRole.rank(PosRole.branchManager), greaterThan(PosRole.rank(PosRole.cashier)));
    });
  });
}
