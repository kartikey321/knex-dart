import 'package:custom_lint_builder/custom_lint_builder.dart';

// ── Dialect-capability rules ────────────────────────────────────────────────
import 'src/rules/dialect_unsupported_full_outer_join_rule.dart';
import 'src/rules/dialect_unsupported_lateral_join_rule.dart';
import 'src/rules/dialect_unsupported_on_conflict_merge_rule.dart';
import 'src/rules/dialect_unsupported_returning_rule.dart';
// New dialect rules
import 'src/rules/dialect_unsupported_cte_rule.dart';
import 'src/rules/dialect_unsupported_window_functions_rule.dart';
import 'src/rules/dialect_unsupported_json_rule.dart';
import 'src/rules/dialect_unsupported_intersect_except_rule.dart';

// ── Literal value rules ─────────────────────────────────────────────────────
import 'src/rules/invalid_where_operator_rule.dart';
import 'src/rules/where_null_value_rule.dart';
import 'src/rules/invalid_order_direction_rule.dart';

// ── Type-inference rules ────────────────────────────────────────────────────
import 'src/rules/value_type_check_rules.dart';

PluginBase createPlugin() => _KnexDartLintPlugin();

class _KnexDartLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) {
    return [
      // Dialect-capability rules (8)
      DialectUnsupportedReturningRule(),
      DialectUnsupportedFullOuterJoinRule(),
      DialectUnsupportedLateralJoinRule(),
      DialectUnsupportedOnConflictMergeRule(),
      DialectUnsupportedCteRule(),
      DialectUnsupportedWindowFunctionsRule(),
      DialectUnsupportedJsonRule(),
      DialectUnsupportedIntersectExceptRule(),

      // Literal value rules (3)
      InvalidWhereOperatorRule(),
      WhereNullValueRule(),
      InvalidOrderDirectionRule(),

      // Type-inference rules (3) — WARNING severity
      LimitNonIntArgumentRule(),
      InsertWrongValueTypeRule(),
      WhereNullTypedValueRule(),
    ];
  }
}
