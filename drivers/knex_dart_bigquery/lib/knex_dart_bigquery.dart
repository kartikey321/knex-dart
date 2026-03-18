/// Google BigQuery driver for knex_dart.
///
/// Example:
/// ```dart
/// import 'package:knex_dart_bigquery/knex_dart_bigquery.dart';
///
/// final db = KnexBigQuery(
///   projectId: 'my-gcp-project',
///   token: 'ya29.oauth_token',
///   defaultDataset: 'analytics',
///   location: 'US',
/// );
///
/// final rows = await db.select(
///   db.queryBuilder().from('page_views').limit(100),
/// );
///
/// db.close();
/// ```
library;

export 'src/bigquery_client.dart';
export 'src/knex_bigquery.dart';
