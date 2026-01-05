import '../client/client.dart';
import 'schema_builder.dart';

/// Abstract base class for schema compilers
///
/// Stub implementation - full implementation in Week 6-7.
abstract class SchemaCompiler {
  final Client client;
  final SchemaBuilder builder;

  SchemaCompiler(this.client, this.builder);
}
