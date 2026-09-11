# Multi-tenant POS platform

POS for Windows, Android, and iOS. Stores are data, not hard-coded apps.

## Current stack

- Flutter + BLoC + GetIt + Hive
- Firebase Authentication + Cloud Firestore
- ESC/POS receipts (58mm / 80mm)

## Who does what

1. **Platform Super Admin** (first account) creates businesses and each store’s Business Admin.
2. **Business Admin** signs in, then manages catalog, stock, staff, branches, and settings, and can also use POS.
3. **Branch Manager** can adjust stock, see reports, and sell.
4. **Cashier** uses POS, orders, and receipts only.

A new shop is never created by a cashier. The platform owner adds the business and the admin login; that admin invites cashiers.

## Firebase

Project: `pos-platform-2a8af`. Client config is in `app/lib/config/firebase/firebase_options.dart`.

1. Enable Email/Password auth and Cloud Firestore.
2. **Publish** `firestore.rules` (production mode needs these rules).
3. Add `127.0.0.1` to Auth authorized domains.

## Run

```bash
cd app
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173
```

First launch: **Create platform owner** with your email. Then **New business** and give that admin their password. They sign in on a till and add products or seed a sample catalog when you create the store.
