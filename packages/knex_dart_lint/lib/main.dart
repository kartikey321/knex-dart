import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/dialect_unsupported_cte_rule.dart';
import 'src/rules/dialect_unsupported_full_outer_join_rule.dart';
import 'src/rules/dialect_unsupported_intersect_except_rule.dart';
import 'src/rules/dialect_unsupported_json_rule.dart';
import 'src/rules/dialect_unsupported_lateral_join_rule.dart';
import 'src/rules/dialect_unsupported_on_conflict_merge_rule.dart';
import 'src/rules/dialect_unsupported_returning_rule.dart';
import 'src/rules/dialect_unsupported_window_functions_rule.dart';
import 'src/rules/invalid_order_direction_rule.dart';
import 'src/rules/invalid_where_operator_rule.dart';
import 'src/rules/raw_null_identifier_binding_rule.dart';
import 'src/rules/value_type_check_rules.dart';
import 'src/rules/where_null_value_rule.dart';

final plugin = _KnexDartLintPlugin();

class _KnexDartLintPlugin extends Plugin {
  @override
  String get name => 'knex_dart_lint';

  @override
  void register(PluginRegistry registry) {
    // Always-on warning rules.
    registry.registerWarningRule(DialectUnsupportedReturningRule());
    registry.registerWarningRule(DialectUnsupportedFullOuterJoinRule());
    registry.registerWarningRule(DialectUnsupportedLateralJoinRule());
    registry.registerWarningRule(DialectUnsupportedOnConflictMergeRule());
    registry.registerWarningRule(DialectUnsupportedCteRule());
    registry.registerWarningRule(DialectUnsupportedWindowFunctionsRule());
    registry.registerWarningRule(DialectUnsupportedJsonRule());
    registry.registerWarningRule(DialectUnsupportedIntersectExceptRule());
    registry.registerWarningRule(InvalidWhereOperatorRule());
    registry.registerWarningRule(InvalidOrderDirectionRule());
    registry.registerWarningRule(RawNullIdentifierBindingRule());
    registry.registerWarningRule(LimitNonIntArgumentRule());
    registry.registerWarningRule(InsertWrongValueTypeRule());
    registry.registerWarningRule(WhereNullTypedValueRule());
    // Opt-in lint rules (enable in analysis_options.yaml diagnostics section).
    registry.registerLintRule(WhereNullValueRule());
  }
}
