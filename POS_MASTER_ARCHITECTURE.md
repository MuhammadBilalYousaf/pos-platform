# POS MASTER ARCHITECTURE & DEVELOPMENT RULES

**Project:** Multi-Tenant POS System\
**Initial Business:** TurknRoll\
**Target Platforms:** Windows Desktop + Android/iOS Mobile\
**Document Purpose:** Master technical contract for Cursor / AI-assisted
development

**Temporary override (2026-09-08):** the developer switched the live
app to Firebase Auth + Cloud Firestore only. MySQL and the Node API are
not used by Flutter until this override is reversed.

------------------------------------------------------------------------

------------------------------------------------------------------------

## 1. MASTER RULE

This document is the **source of truth for the technical stack and
architectural direction of this project**.

Cursor and all future AI-assisted development must follow this document
unless the developer explicitly changes this master specification.

Do not introduce a different framework, database, state-management
solution, authentication system, local database, or architecture pattern
without explicit approval.

The application must be developed as a **production-quality, scalable,
multi-tenant POS platform**, not as a disposable demo or a
TurknRoll-only application.

TurknRoll is the first configured business. The same application must
later support businesses such as:

-   Ice cream shops
-   Pizza shops
-   Cafes
-   Restaurants
-   Bakeries
-   Other food/retail businesses

------------------------------------------------------------------------

# 2. APPROVED TECHNOLOGY STACK

## Frontend

-   **Flutter**
-   **Dart**
-   **BLoC / Cubit** for state management
-   **Clean Architecture**
-   **GetIt** for Dependency Injection
-   **Hive** for local/offline data
-   **Flutter Secure Storage** for sensitive local data

## Backend

-   **Node.js**
-   **TypeScript**
-   REST API architecture
-   Backend business logic must remain on the server where appropriate

## Database

-   **MySQL** as the primary production database
-   MySQL must be accessed through the Node.js backend
-   Flutter must NEVER connect directly to MySQL

## Authentication

-   **Firebase Authentication**
-   Firebase Authentication is used for identity/authentication only
-   MySQL remains the application's primary business data store

## Desktop

-   Flutter Windows Desktop

## Mobile

-   Flutter Android
-   Flutter iOS

## Printing

-   ESC/POS thermal receipt printing
-   Support common 58mm and 80mm receipt printers

------------------------------------------------------------------------

# 3. ARCHITECTURE OVERVIEW

The high-level architecture must remain:

``` text
                    ┌─────────────────────────┐
                    │       Flutter App       │
                    │                         │
                    │ Windows + Android + iOS │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │ BLoC / Cubit            │
                    │ Presentation Logic      │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │ Repository Layer        │
                    │ Domain Abstractions     │
                    └───────┬─────────┬───────┘
                            │         │
                    Remote API       Local
                            │         │
                            ▼         ▼
                    ┌───────────┐  ┌───────────┐
                    │ Node.js   │  │ Hive      │
                    │ TypeScript│  │ Local DB  │
                    │ REST API  │  │ / Cache   │
                    └─────┬─────┘  └─────┬─────┘
                          │              │
                          ▼              │
                    ┌───────────┐       │
                    │   MySQL   │◄──────┘
                    │ Main DB   │  Sync
                    └───────────┘

                    Firebase Authentication
                           │
                           ▼
                    User Identity / Token
```

------------------------------------------------------------------------

# 4. NON-NEGOTIABLE ARCHITECTURAL RULES

## Rule 1 --- Flutter must never access MySQL directly

Incorrect:

``` text
Flutter → MySQL
```

Correct:

``` text
Flutter → Node.js API → MySQL
```

This rule must never be violated.

------------------------------------------------------------------------

## Rule 2 --- Firebase Authentication is not the business database

Firebase Authentication handles:

-   Login
-   Logout
-   Identity
-   Authentication tokens
-   Password authentication where applicable

MySQL handles:

-   Users/business profiles
-   Roles
-   Branches
-   Products
-   Categories
-   Inventory
-   Recipes
-   Orders
-   Payments
-   Reports
-   Audit logs
-   Other application/business data

Firebase Firestore must NOT be introduced as a replacement for MySQL
unless explicitly approved.

------------------------------------------------------------------------

## Rule 3 --- Multi-tenancy must exist from the beginning

The application must not be designed as:

``` text
TurknRoll → Products → Orders
```

It must be designed as:

``` text
Platform
   │
   ├── Business A
   │      ├── Branch
   │      ├── Users
   │      ├── Products
   │      ├── Inventory
   │      └── Orders
   │
   ├── Business B
   │      ├── Branch
   │      ├── Users
   │      ├── Products
   │      ├── Inventory
   │      └── Orders
   │
   └── Business C
```

Each business must have complete logical data isolation.

------------------------------------------------------------------------

## Rule 4 --- Never hard-code TurknRoll into the application

TurknRoll is initial seed/master data.

Do not hard-code:

-   Business name
-   Product names
-   Prices
-   Categories
-   Branches
-   Employees
-   Product IDs
-   Branch IDs
-   Business IDs
-   Recipes

These must come from the backend/database.

------------------------------------------------------------------------

## Rule 5 --- Never put business logic directly in UI widgets

Bad:

``` text
UI Widget
  → calculate inventory
  → calculate order
  → update database
```

Correct:

``` text
UI
 ↓
BLoC/Cubit
 ↓
Use Case / Domain Logic
 ↓
Repository
 ↓
API / Local Data Source
```

------------------------------------------------------------------------

# 5. FLUTTER ARCHITECTURE

Use Clean Architecture with feature-based organization.

Recommended structure:

``` text
lib/
├── core/
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── helpers/
│   ├── network/
│   ├── services/
│   ├── storage/
│   ├── theme/
│   ├── utils/
│   └── widgets/
│
├── config/
│   ├── routes/
│   ├── environment/
│   └── dependency_injection/
│
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── business/
│   ├── branches/
│   ├── employees/
│   ├── products/
│   ├── categories/
│   ├── recipes/
│   ├── inventory/
│   ├── purchases/
│   ├── stock_transfers/
│   ├── pos/
│   ├── orders/
│   ├── payments/
│   ├── reports/
│   ├── printing/
│   └── settings/
│
└── main.dart
```

Each feature should preferably contain:

``` text
feature/
├── data/
│   ├── datasources/
│   ├── models/
│   └── repositories/
│
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
│
└── presentation/
    ├── bloc/
    ├── pages/
    └── widgets/
```

Do not create unnecessarily deep structures for trivial features, but
preserve the separation of concerns.

------------------------------------------------------------------------

# 6. STATE MANAGEMENT --- BLoC / CUBIT

Use **flutter_bloc**.

Use BLoC/Cubit for:

-   Authentication state
-   Business selection
-   Branch selection
-   Product state
-   Inventory state
-   Cart state
-   Order state
-   Payment state
-   Printing state
-   Synchronization state
-   Dashboard/report state

Examples:

``` text
AuthBloc
BusinessBloc
BranchBloc
ProductBloc
InventoryBloc
CartBloc
OrderBloc
PaymentBloc
PrinterBloc
SyncBloc
```

Do not create a BLoC for every tiny widget.

Keep state management predictable and testable.

Do not place database queries directly inside BLoCs.

BLoCs should communicate with use cases/repositories.

------------------------------------------------------------------------

# 7. DEPENDENCY INJECTION

Use **GetIt** for dependency injection.

Register:

-   API client
-   Firebase authentication service
-   Secure storage service
-   Hive/local database service
-   Repositories
-   Use cases
-   Sync service
-   Printer service
-   Connectivity service
-   Other infrastructure services

Example dependency direction:

``` text
Presentation
      ↓
BLoC
      ↓
Use Case
      ↓
Repository Interface
      ↓
Repository Implementation
      ↓
Remote / Local Data Source
```

Avoid creating service objects repeatedly inside widgets.

------------------------------------------------------------------------

# 8. NODE.JS BACKEND

Use:

-   Node.js
-   TypeScript
-   REST APIs

The backend is responsible for:

-   Authentication verification
-   Authorization
-   Business rules
-   Multi-tenant access control
-   Validation
-   Database operations
-   Transactions
-   Inventory calculations
-   Order processing
-   Reporting queries
-   Audit logging
-   Synchronization endpoints

Recommended backend structure:

``` text
backend/
├── src/
│   ├── config/
│   ├── middleware/
│   ├── modules/
│   │   ├── auth/
│   │   ├── businesses/
│   │   ├── branches/
│   │   ├── users/
│   │   ├── products/
│   │   ├── inventory/
│   │   ├── recipes/
│   │   ├── orders/
│   │   ├── payments/
│   │   ├── reports/
│   │   └── sync/
│   │
│   ├── database/
│   ├── routes/
│   ├── services/
│   ├── utils/
│   └── app.ts
│
└── server.ts
```

Use TypeScript strictly.

Do not use `any` unnecessarily.

------------------------------------------------------------------------

# 9. MYSQL DATABASE

MySQL is the **single source of truth for server-side business data**.

Use UUIDs or equivalent globally unique identifiers where appropriate.

Use proper:

-   Foreign keys
-   Indexes
-   Unique constraints
-   Check constraints where supported
-   Transactions
-   Decimal types for money
-   Appropriate date/time types

Never use floating-point numbers for monetary values.

Use:

``` text
DECIMAL
```

for money.

------------------------------------------------------------------------

# 10. CORE DATABASE MODEL

The database must support at least:

``` text
businesses
branches
users
roles
permissions
user_roles

categories
products
product_variants
product_options

units
ingredients
recipes
recipe_items

inventory
inventory_transactions
stock_adjustments

stock_transfers
stock_transfer_items

suppliers
purchases
purchase_items

orders
order_items
payments
discounts

printers
settings
audit_logs
```

Additional tables can be introduced when required by an approved
feature.

------------------------------------------------------------------------

# 11. MULTI-TENANT DATABASE RULE

Business-owned records must include:

``` text
business_id
```

Branch-specific records must include:

``` text
branch_id
```

Example:

``` text
orders
├── id
├── business_id
├── branch_id
├── cashier_id
├── total
└── created_at
```

Every backend query must be scoped to the authenticated business.

Never trust `business_id` supplied by the Flutter client.

The Node.js backend must determine the user's authorized business/branch
from the authenticated identity and database records.

------------------------------------------------------------------------

# 12. FIREBASE AUTHENTICATION

Use Firebase Authentication for user authentication.

Login flow:

``` text
Flutter
   ↓
Firebase Authentication
   ↓
Firebase ID Token
   ↓
Node.js
   ↓
Verify Firebase Token
   ↓
Find application user in MySQL
   ↓
Resolve business / branch / role
   ↓
Authorize request
```

Store the Firebase UID in MySQL:

``` text
users
├── id
├── firebase_uid
├── business_id
├── branch_id
├── role_id
├── name
├── email
└── status
```

Never store passwords manually in MySQL.

Never expose Firebase Admin/service credentials to Flutter.

------------------------------------------------------------------------

# 13. SECURE STORAGE

Use **Flutter Secure Storage** only for sensitive local information.

Examples:

-   Authentication/session information where required
-   Secure tokens
-   Device identifiers
-   Other sensitive configuration

Do not put sensitive credentials into ordinary Hive boxes.

------------------------------------------------------------------------

# 14. HIVE / OFFLINE STORAGE

Hive is the local persistence/cache layer.

Use it for:

-   Cached products
-   Categories
-   Prices
-   Branch configuration
-   POS settings
-   Current cart
-   Pending orders
-   Sync queue
-   Other carefully selected offline data

Hive is NOT the primary server database.

MySQL remains the source of truth.

------------------------------------------------------------------------

# 15. OFFLINE-FIRST POS

A physical POS must continue operating during temporary internet
outages.

Expected behavior:

``` text
Internet Available
        ↓
Flutter
        ↓
API
        ↓
MySQL
```

When internet is unavailable:

``` text
Flutter
   ↓
BLoC
   ↓
Local Repository
   ↓
Hive
   ↓
Order marked PENDING_SYNC
```

The cashier should still be able to:

-   Create order
-   Complete order
-   Take payment
-   Print receipt
-   Continue selling

When internet returns:

``` text
Hive Pending Queue
        ↓
Sync Service
        ↓
Node.js
        ↓
MySQL
        ↓
Mark SYNCED
```

------------------------------------------------------------------------

# 16. SYNC SAFETY

Offline synchronization must be designed to prevent duplicate orders.

Every locally created transaction should have an idempotency key/local
UUID.

If synchronization is retried:

``` text
Same local order
      ↓
Same idempotency key
      ↓
Backend detects existing transaction
      ↓
No duplicate order
```

Possible sync states:

``` text
PENDING_SYNC
SYNCING
SYNCED
SYNC_FAILED
```

Keep failed synchronization records available for retry/debugging.

------------------------------------------------------------------------

# 17. INVENTORY SYSTEM

Inventory is a core business feature.

Do not simply store:

``` text
ice_cream = 100
```

Use inventory items and transaction history.

Supported units should include:

``` text
PCS
G
KG
ML
L
DOZEN
BOX
PACK
```

Use base units internally where practical.

Example:

``` text
Purchase:
10 KG

Internal:
10000 G

Sale:
100 G

Remaining:
9900 G
```

Inventory quantities must support appropriate precision.

------------------------------------------------------------------------

# 18. RECIPE / BOM SYSTEM

Products can have recipes.

Example:

``` text
Mango Shake

Milk       250 ML
Mango       80 G
Ice Cream  100 G
Sugar       20 G
Cup          1 PCS
Straw        1 PCS
```

Selling one Mango Shake should create the corresponding inventory
deductions.

Every inventory-affecting action must create an inventory transaction.

Do not silently modify stock.

Transaction types should include:

``` text
PURCHASE
SALE
SALE_REVERSAL
TRANSFER_IN
TRANSFER_OUT
ADJUSTMENT_IN
ADJUSTMENT_OUT
WASTE
RETURN
```

------------------------------------------------------------------------

# 19. ORDER SYSTEM

Order workflow:

``` text
Employee Login
      ↓
Select Branch
      ↓
New Order
      ↓
Select Category
      ↓
Select Product
      ↓
Select Variant / Options
      ↓
Add to Cart
      ↓
Modify Quantity
      ↓
Discount
      ↓
Tax
      ↓
Payment
      ↓
Confirm
      ↓
Create Order
      ↓
Create Order Items
      ↓
Create Payment
      ↓
Deduct Inventory
      ↓
Generate Receipt
      ↓
Print Receipt
      ↓
Completed
```

Critical order operations must be atomic on the backend.

------------------------------------------------------------------------

# 20. ORDER STATUS

Use:

``` text
DRAFT
HELD
COMPLETED
CANCELLED
REFUNDED
PARTIALLY_REFUNDED
```

Never delete completed orders.

Use cancellation/refund/reversal records and audit history.

------------------------------------------------------------------------

# 21. PAYMENT METHODS

Initial supported methods:

``` text
CASH
CARD
BANK_TRANSFER
EASYPAISA
JAZZCASH
OTHER
```

Payment records should contain appropriate information such as:

-   Order ID
-   Payment method
-   Amount
-   Reference number where applicable
-   Status
-   Timestamp
-   Cashier

Design the payment system so additional methods can be added later.

------------------------------------------------------------------------

# 22. ROLE-BASED ACCESS

Initial roles:

## Platform Super Admin

Can manage the overall POS platform and businesses.

## Business Admin

Can manage:

-   Products
-   Categories
-   Prices
-   Recipes
-   Inventory
-   Employees
-   Branches
-   Reports
-   Business settings

## Branch Manager

Can manage:

-   Branch inventory
-   Branch employees
-   Branch sales
-   Stock adjustments
-   Branch reports

## Employee / Cashier

Can:

-   Create orders
-   Modify cart
-   Take payment
-   Print receipts
-   View permitted order information

Employees must not be allowed to arbitrarily change:

-   Product master data
-   Recipes
-   Inventory
-   Completed orders
-   Permissions

Authorization must be enforced by the backend, not only by hiding UI
buttons.

------------------------------------------------------------------------

# 23. RECEIPT PRINTING

Use an abstraction such as:

``` text
PrinterService
```

Do not hard-code a single printer.

Support:

-   ESC/POS
-   58mm
-   80mm

Receipt should include:

``` text
Business Name
Branch Name
Address
Phone
Order Number
Date/Time
Cashier
Items
Quantity
Unit Price
Line Total
Subtotal
Discount
Tax
Grand Total
Payment Method
Footer
```

Allow printer settings to be configured per branch/device.

------------------------------------------------------------------------

# 24. DESKTOP REQUIREMENTS

Windows Desktop is the primary POS environment.

Prioritize:

-   Fast startup
-   Fast product search
-   Keyboard support
-   Mouse support
-   Touch-friendly controls
-   Thermal printing
-   Offline operation
-   Large readable POS controls
-   Minimal unnecessary animations

The desktop UI must not simply be a stretched mobile screen.

Use responsive/adaptive layouts appropriate for desktop.

------------------------------------------------------------------------

# 25. MOBILE REQUIREMENTS

The same Flutter project must support mobile.

Mobile can provide:

-   Owner dashboard
-   Sales reports
-   Inventory monitoring
-   Product management where appropriate
-   Branch monitoring
-   Employee monitoring
-   POS functions where required

Mobile screens must use responsive layouts rather than copying desktop
dimensions.

Do not compromise desktop UX just to make one layout work everywhere.

Use shared domain/data logic while allowing platform-appropriate
presentation.

------------------------------------------------------------------------

# 26. BUSINESS BRANDING

Business configuration should eventually support:

``` text
Business Name
Logo
Primary Color
Secondary Color
Address
Phone
Currency
Tax Settings
Receipt Header
Receipt Footer
```

TurknRoll branding is the initial configuration.

Do not hard-code TurknRoll branding throughout the application.

------------------------------------------------------------------------

# 27. TURKNROLL INITIAL DATA

The uploaded TurknRoll menu is the initial source for seed/master
product data.

The menu contains categories such as:

-   Turkish Ice Cream
-   Soft Ice Cream
-   Sundae
-   Fresh Mint
-   Lemonade
-   Water
-   Kids Cup
-   Boba Cup
-   Cold Coffee
-   Shake
-   Brownie
-   Molten Lawa

Product names and prices should be entered as database
seed/configuration data and remain editable from the admin interface.

Do not implement menu items as hard-coded Flutter widgets.

------------------------------------------------------------------------

# 28. API DESIGN

Use versioned REST APIs where appropriate.

Example:

``` text
/api/v1/auth
/api/v1/businesses
/api/v1/branches
/api/v1/users
/api/v1/products
/api/v1/categories
/api/v1/inventory
/api/v1/recipes
/api/v1/orders
/api/v1/payments
/api/v1/reports
/api/v1/sync
```

Use proper HTTP status codes.

Validate all request payloads.

Return consistent API response/error structures.

Never expose internal stack traces or raw database errors to clients.

------------------------------------------------------------------------

# 29. SECURITY REQUIREMENTS

Mandatory:

-   Firebase token verification on backend
-   Role-based authorization
-   Business-level authorization
-   Branch-level authorization
-   Input validation
-   Parameterized queries / ORM-safe queries
-   No hard-coded secrets
-   Environment variables
-   No database credentials in Flutter
-   No Firebase Admin credentials in Flutter
-   HTTPS in production
-   Audit logging for sensitive actions

Never trust values from the client simply because the UI restricts them.

------------------------------------------------------------------------

# 30. TRANSACTIONS

Use MySQL transactions for critical operations.

For completing an order:

``` text
BEGIN

Create Order
Create Order Items
Create Payment
Create Inventory Transactions
Update Inventory

COMMIT
```

If any critical step fails:

``` text
ROLLBACK
```

The system must never leave inconsistent states such as:

-   Paid order without payment record
-   Payment without order
-   Inventory deducted without a valid sale
-   Completed order without inventory transaction

------------------------------------------------------------------------

# 31. INVENTORY AUDITABILITY

Every inventory change must be traceable.

An administrator should be able to answer:

> Why did this item have this quantity?

The system must provide stock movement history showing:

``` text
Date
Branch
Item
Transaction Type
Quantity
Reference
User
Previous Stock
New Stock
```

------------------------------------------------------------------------

# 32. REPORTING

Initial reports should include:

-   Sales Report
-   Product Sales Report
-   Category Sales Report
-   Branch Sales Report
-   Employee Sales Report
-   Payment Report
-   Inventory Report
-   Low Stock Report
-   Purchase Report
-   Stock Movement Report
-   Discount Report
-   Cancellation Report
-   Refund Report

Support filtering by:

-   Date
-   Branch
-   Employee
-   Product
-   Category
-   Payment method

------------------------------------------------------------------------

# 33. PERFORMANCE

POS performance is a priority.

Avoid unnecessary network requests.

Use:

-   Local caching
-   Hive
-   Pagination
-   Database indexes
-   Efficient API queries
-   Debounced search where appropriate
-   Lazy loading for large datasets

The main POS screen should feel immediate.

Do not fetch the entire database every time the POS screen opens.

------------------------------------------------------------------------

# 34. ERROR HANDLING

Use structured error handling across Flutter and Node.js.

Employee-facing messages should be understandable.

Examples:

``` text
Unable to complete order. Please try again.

Insufficient stock for this item.

Printer unavailable. Order completed but receipt could not be printed.

Internet unavailable. Order saved offline.

You do not have permission to perform this action.
```

Do not show raw SQL errors, stack traces, or internal implementation
details.

------------------------------------------------------------------------

# 35. LOGGING

Backend should maintain useful structured logs.

Log:

-   API errors
-   Authentication failures
-   Sync failures
-   Critical business operation failures
-   Database failures

Do not log:

-   Passwords
-   Sensitive authentication credentials
-   Secrets
-   Unnecessary personal information

------------------------------------------------------------------------

# 36. TESTING

Flutter tests should cover:

-   BLoC/Cubit behavior
-   Cart calculations
-   Order calculations
-   Discount calculations
-   Recipe calculations
-   Inventory calculations
-   Offline behavior
-   Sync behavior
-   Permission logic

Backend tests should cover:

-   Authentication
-   Authorization
-   Multi-tenant isolation
-   Product APIs
-   Inventory
-   Recipes
-   Orders
-   Payments
-   Stock transfers
-   Synchronization
-   Idempotency
-   Reports

Critical inventory and order logic must have strong automated test
coverage.

------------------------------------------------------------------------

# 37. DEVELOPMENT PROCESS

Do NOT generate the entire application in one massive implementation.

Develop incrementally.

Recommended sequence:

``` text
PHASE 1
Project setup
Architecture
Flutter configuration
BLoC
DI
Theme
Environment configuration

PHASE 2
Firebase Authentication
User model
Roles
Business context
Branch context

PHASE 3
Node.js backend
MySQL database
Database migrations
Core APIs
Authentication verification

PHASE 4
Business / Branch management

PHASE 5
Categories / Products / Variants

PHASE 6
Ingredients / Units / Recipes

PHASE 7
Inventory / Stock movements

PHASE 8
POS / Cart / Order workflow

PHASE 9
Payments

PHASE 10
Receipt printing

PHASE 11
Offline Hive storage

PHASE 12
Synchronization engine

PHASE 13
Reports / Dashboard

PHASE 14
Audit logs / Security hardening

PHASE 15
Testing / Optimization / Production readiness
```

------------------------------------------------------------------------

# 38. CURSOR DEVELOPMENT RULE

Before implementing any major feature:

1.  Read this master document.
2.  Inspect the existing architecture.
3.  Inspect existing code before creating new files.
4.  Reuse existing abstractions where appropriate.
5.  Do not duplicate services or models.
6.  Do not replace approved technologies.
7.  Do not introduce a new architecture without approval.
8.  Do not break existing functionality to implement a new feature.
9.  Keep changes modular.
10. Explain architectural changes before making significant changes.

When implementing a feature, identify:

``` text
Frontend
BLoC
Domain
Repository
API
Backend
Database
Local Storage
Sync
Testing
```

where applicable.

------------------------------------------------------------------------

# 39. DO NOT DO THESE THINGS

Do NOT:

-   Connect Flutter directly to MySQL
-   Put SQL credentials in Flutter
-   Use Firebase Firestore as the main database
-   Hard-code products
-   Hard-code prices
-   Hard-code business IDs
-   Hard-code branch IDs
-   Store passwords manually
-   Put all application logic in widgets
-   Put all application logic in BLoCs
-   Create one giant Dart file
-   Create one giant Node.js file
-   Delete completed orders
-   Modify inventory without transaction history
-   Trust client-supplied business IDs
-   Assume internet is always available
-   Build only for TurknRoll
-   Replace BLoC with another state management solution without approval
-   Replace MySQL with another database without approval
-   Replace Node.js with another backend without approval
-   Add unnecessary dependencies

------------------------------------------------------------------------

# 40. FUTURE EXTENSIBILITY

The architecture should allow future features such as:

-   Customer management
-   Loyalty
-   Online ordering
-   Delivery
-   Kitchen Display System
-   Barcode scanning
-   Supplier management
-   Purchase orders
-   Advanced accounting
-   Owner mobile dashboard
-   SaaS subscriptions
-   Multi-currency
-   Advanced analytics

Do not implement future features unless explicitly requested.

Design for extensibility without over-engineering the current release.

------------------------------------------------------------------------

# 41. PRODUCTION QUALITY STANDARD

This application is intended to become a real POS product and
potentially a reusable SaaS platform.

Therefore prioritize:

1.  Correctness
2.  Data integrity
3.  Security
4.  Multi-tenant isolation
5.  Offline reliability
6.  Maintainability
7.  Testability
8.  Performance
9.  Good UX
10. Scalability

Do not optimize for "getting a demo working" at the expense of these
principles.

------------------------------------------------------------------------

# 42. MASTER TECHNOLOGY DECISION

Unless explicitly changed by the developer, the following decisions are
FINAL:

  Area                     Approved Technology
  ------------------------ --------------------------
  Frontend                 Flutter
  Language                 Dart
  State Management         BLoC / Cubit
  Architecture             Clean Architecture
  Dependency Injection     GetIt
  Backend                  Node.js
  Backend Language         TypeScript
  API                      REST
  Main Database            MySQL
  Authentication           Firebase Authentication
  Local Database / Cache   Hive
  Secure Local Storage     Flutter Secure Storage
  Desktop                  Flutter Windows
  Mobile                   Flutter Android / iOS
  Receipt Printing         ESC/POS
  Multi-Tenancy            Business + Branch scoped
  Offline                  Hive + Sync Engine

------------------------------------------------------------------------

# 43. FINAL INSTRUCTION TO CURSOR

Treat this document as the **MASTER TECHNICAL CONTRACT** for the
project.

Before generating or modifying code, ensure the implementation complies
with this architecture.

If an implementation request conflicts with this document:

1.  Identify the conflict.
2.  Do not silently change the architecture.
3.  Explain the conflict.
4.  Follow the master architecture unless the developer explicitly
    approves a change.

The goal is to build a **real, scalable, secure, multi-tenant POS
application for desktop and mobile**, beginning with TurknRoll but
capable of supporting completely different businesses without rewriting
the core system.
