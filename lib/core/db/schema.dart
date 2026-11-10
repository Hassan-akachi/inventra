import 'package:powersync/powersync.dart';

/// Local database schema for Inventra.
///
/// PowerSync adds an `id` TEXT primary key to every table automatically.
/// Money is stored as INTEGER minor units (kobo, cents, fen).
/// Dates are ISO-8601 TEXT; expiry dates are `yyyy-MM-dd`.
/// The full schema is defined now so later phases need no migration.

List<Column> _audit() => const [
      Column.text('business_id'),
      Column.text('created_at'),
      Column.text('updated_at'),
      Column.text('updated_by'),
      Column.text('deleted_at'),
    ];

final schema = Schema([
  // Accounts
  Table('businesses', [
    const Column.text('name'),
    const Column.text('owner_id'),
    const Column.text('default_currency'),
    const Column.text('report_currency'),
    const Column.text('phone'),
    const Column.text('address'),
    const Column.text('receipt_footer'),
    const Column.text('created_at'),
    const Column.text('updated_at'),
  ]),
  Table('members', [
    ..._audit(),
    const Column.text('user_id'),
    const Column.text('display_name'),
    const Column.text('role'), // owner | staff
    const Column.text('permissions'), // JSON list, e.g. ["edit_items"]
    const Column.text('shop_ids'), // JSON list of main_category ids
  ]),

  // Catalogue
  Table('main_categories', [
    ..._audit(),
    const Column.text('name'),
    const Column.text('currency'),
    const Column.integer('is_temporary'),
    const Column.text('archived_at'),
  ]),
  Table('item_categories', [
    ..._audit(),
    const Column.text('main_category_id'),
    const Column.text('name'),
    const Column.integer('is_temporary'),
    const Column.text('archived_at'),
  ], indexes: [
    Index('by_shop', [IndexedColumn('main_category_id')]),
  ]),
  Table('items', [
    ..._audit(),
    const Column.text('main_category_id'),
    const Column.text('item_category_id'),
    const Column.text('name'),
    const Column.text('barcode'),
    const Column.text('description'),
    const Column.text('base_unit'),
    const Column.text('currency'),
    const Column.integer('cost_price'),
    const Column.integer('selling_price'),
    const Column.integer('low_stock_level'),
    const Column.text('size'),
    const Column.integer('discontinued'),
    const Column.text('expiry_date'),
    const Column.text('image_path'),
    const Column.text('note'),
  ], indexes: [
    Index('by_shop', [IndexedColumn('main_category_id')]),
    Index('by_barcode', [IndexedColumn('barcode')]),
  ]),
  Table('item_units', [
    ..._audit(),
    const Column.text('item_id'),
    const Column.text('name'), // Pack, Dozen, Carton
    const Column.text('barcode'),
    const Column.integer('units_per_pack'),
    const Column.integer('selling_price'),
  ], indexes: [
    Index('by_item', [IndexedColumn('item_id')]),
    Index('by_barcode', [IndexedColumn('barcode')]),
  ]),
  Table('price_history', [
    const Column.text('business_id'),
    const Column.text('item_id'),
    const Column.text('unit_id'),
    const Column.text('price_type'), // cost | selling
    const Column.integer('old_price'),
    const Column.integer('new_price'),
    const Column.text('changed_at'),
    const Column.text('changed_by'),
  ], indexes: [
    Index('by_item', [IndexedColumn('item_id')]),
  ]),
  Table('suppliers', [
    ..._audit(),
    const Column.text('company_name'),
    const Column.text('contact_name'),
    const Column.text('phone'),
    const Column.text('email'),
    const Column.text('address'),
    const Column.text('note'),
  ]),
  Table('item_suppliers', [
    ..._audit(),
    const Column.text('item_id'),
    const Column.text('supplier_id'),
    const Column.integer('supply_price'),
    const Column.text('currency'),
    const Column.text('last_supplied_at'),
  ], indexes: [
    Index('by_item', [IndexedColumn('item_id')]),
    Index('by_supplier', [IndexedColumn('supplier_id')]),
  ]),

  // Sales and stock (phase 2+)
  Table('customers', [
    ..._audit(),
    const Column.text('name'),
    const Column.text('phone'),
    const Column.text('email'),
    const Column.text('address'),
    const Column.text('note'),
  ]),
  Table('sales', [
    ..._audit(),
    const Column.text('receipt_no'),
    const Column.text('main_category_id'),
    const Column.text('customer_id'),
    const Column.text('currency'),
    const Column.integer('subtotal'),
    const Column.integer('discount'),
    const Column.integer('total'),
    const Column.integer('amount_paid'),
    const Column.text('payment_status'), // paid | partial | unpaid
    const Column.text('sold_at'),
    const Column.text('sold_by'),
    const Column.text('voided_at'),
    const Column.text('note'),
  ], indexes: [
    Index('by_customer', [IndexedColumn('customer_id')]),
    Index('by_shop_date', [IndexedColumn('main_category_id'), IndexedColumn('sold_at')]),
  ]),
  Table('sale_items', [
    const Column.text('business_id'),
    const Column.text('sale_id'),
    const Column.text('item_id'),
    const Column.text('item_name'),
    const Column.text('unit_id'),
    const Column.text('unit_name'),
    const Column.integer('units_per_pack'),
    const Column.integer('quantity'),
    const Column.integer('base_quantity'),
    const Column.integer('unit_price'),
    const Column.integer('cost_price'),
    const Column.integer('line_total'),
  ], indexes: [
    Index('by_sale', [IndexedColumn('sale_id')]),
    Index('by_item', [IndexedColumn('item_id')]),
  ]),
  Table('payments', [
    const Column.text('business_id'),
    const Column.text('sale_id'),
    const Column.integer('amount'),
    const Column.text('method'), // cash | transfer | pos | other
    const Column.text('paid_at'),
    const Column.text('received_by'),
  ], indexes: [
    Index('by_sale', [IndexedColumn('sale_id')]),
  ]),
  Table('stock_movements', [
    const Column.text('business_id'),
    const Column.text('main_category_id'),
    const Column.text('item_id'),
    const Column.integer('change'), // + in, - out, in base units
    const Column.text('reason'), // opening | sale | void | restock | damaged | missing | returned | correction
    const Column.text('ref_id'),
    const Column.text('note'),
    const Column.text('created_at'),
    const Column.text('created_by'),
  ], indexes: [
    Index('by_item', [IndexedColumn('item_id')]),
  ]),
  Table('restocks', [
    ..._audit(),
    const Column.text('main_category_id'),
    const Column.text('supplier_id'),
    const Column.text('item_id'),
    const Column.text('unit_id'),
    const Column.text('unit_name'),
    const Column.integer('units_per_pack'),
    const Column.integer('quantity'), // in unit_name
    const Column.integer('base_quantity'),
    const Column.integer('cost_price'), // per unit_name
    const Column.integer('total_cost'),
    const Column.text('currency'),
    const Column.text('expiry_date'),
    const Column.text('received_at'),
    const Column.text('note'),
  ], indexes: [
    Index('by_item', [IndexedColumn('item_id')]),
    Index('by_shop', [IndexedColumn('main_category_id')]),
  ]),
  Table('expenses', [
    ..._audit(),
    const Column.text('main_category_id'),
    const Column.text('category'),
    const Column.integer('amount'),
    const Column.text('currency'),
    const Column.text('note'),
    const Column.text('spent_at'),
  ]),
  Table('analytics_snapshots', [
    const Column.text('business_id'),
    const Column.text('period_type'), // day | week | month
    const Column.text('period_start'),
    const Column.text('main_category_id'),
    const Column.text('currency'),
    const Column.integer('total_sales'),
    const Column.integer('total_cost'),
    const Column.integer('profit'),
    const Column.integer('items_sold'),
    const Column.integer('stock_value'),
    const Column.text('created_at'),
  ]),
  Table('exchange_rates', [
    const Column.text('business_id'),
    const Column.text('base'),
    const Column.text('quote'),
    const Column.real('rate'),
    const Column.text('source'), // online | manual
    const Column.text('fetched_at'),
  ]),

  // Device-only preferences, never synced. id = setting key.
  Table.localOnly('local_settings', [
    const Column.text('value'),
  ]),
]);
