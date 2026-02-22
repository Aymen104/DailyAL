// Bug Condition Exploration Test for Lint Issues Fix
// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14, 2.15, 2.16**
//
// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
// DO NOT attempt to fix the test or the code when it fails
// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
//
// GOAL: Surface counterexamples that demonstrate the lint violations exist
// EXPECTED OUTCOME: Test FAILS with type assignment errors and inference warnings (this is correct - it proves the bug exists)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bug Condition Exploration - Strict Type Checking Violations', () {
    late ProcessResult analyzeResult;

    setUpAll(() async {
      // Run flutter analyze and capture the output
      analyzeResult = await Process.run(
        'flutter',
        ['analyze', '--no-pub'],
        runInShell: true,
      );
    });

    test('Property 1: Fault Condition - All Lint Violations Present', () {
      // Parse the analyze output
      final String output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();

      // Extract error and warning lines
      final List<String> lines = output.split('\n');
      final List<String> errors = lines.where((line) => line.trim().startsWith('error •')).toList();
      final List<String> warnings = lines.where((line) => line.trim().startsWith('warning •')).toList();

      // Filter for strict type checking violations
      final List<String> typeAssignmentErrors = errors
          .where(
            (line) =>
                line.contains('argument_type_not_assignable') ||
                line.contains("can't be assigned to the parameter type") ||
                line.contains("can't be assigned to a variable of type") ||
                line.contains("can't be returned from the function") ||
                line.contains('invalid_assignment'),
          )
          .toList();

      final List<String> inferenceWarnings = warnings
          .where(
            (line) =>
                line.contains('inference_failure') ||
                line.contains("can't be inferred") ||
                line.contains('type must be explicitly provided') ||
                line.contains("type can't be inferred without"),
          )
          .toList();

      // Document counterexamples found
      print('\n=== BUG CONDITION EXPLORATION RESULTS ===');
      print('Total errors found: ${errors.length}');
      print('Total warnings found: ${warnings.length}');
      print('Type assignment errors (strict-casts violations): ${typeAssignmentErrors.length}');
      print('Type inference warnings (strict-inference violations): ${inferenceWarnings.length}');
      print('\n=== SAMPLE TYPE ASSIGNMENT ERRORS ===');
      for (int i = 0; i < (typeAssignmentErrors.length < 10 ? typeAssignmentErrors.length : 10); i++) {
        print(typeAssignmentErrors[i].trim());
      }
      print('\n=== SAMPLE TYPE INFERENCE WARNINGS ===');
      for (int i = 0; i < (inferenceWarnings.length < 10 ? inferenceWarnings.length : 10); i++) {
        print(inferenceWarnings[i].trim());
      }
      print('\n=== END OF COUNTEREXAMPLES ===\n');

      // CRITICAL: This assertion MUST FAIL on unfixed code
      // When it fails, it proves the bug exists (which is the correct outcome for this exploration test)
      // After the fix is implemented, this same test will pass, confirming the bug is resolved
      expect(
        typeAssignmentErrors.isEmpty && inferenceWarnings.isEmpty,
        isTrue,
        reason: 'EXPECTED FAILURE: Found ${typeAssignmentErrors.length} type assignment errors '
            'and ${inferenceWarnings.length} type inference warnings. '
            'This confirms the bug condition exists. '
            'Violations include:\n'
            '- Dynamic assignments without explicit casts (strict-casts)\n'
            '- Missing type annotations on lambdas, variables, and functions (strict-inference)\n'
            'See console output above for specific file paths, line numbers, and error messages.',
      );
    });

    test('Verify strict type checking rules are enabled', () {
      // Read analysis_options.yaml to confirm strict rules are enabled
      final File analysisOptions = File('analysis_options.yaml');
      expect(analysisOptions.existsSync(), isTrue, reason: 'analysis_options.yaml must exist');

      final String content = analysisOptions.readAsStringSync();
      expect(
        content.contains('strict-casts: true'),
        isTrue,
        reason: 'strict-casts must be enabled',
      );
      expect(
        content.contains('strict-inference: true'),
        isTrue,
        reason: 'strict-inference must be enabled',
      );
      expect(
        content.contains('strict-raw-types: true'),
        isTrue,
        reason: 'strict-raw-types must be enabled',
      );
    });

    test('Document specific violation categories', () {
      final String output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      final List<String> lines = output.split('\n');

      // Category 1: Dynamic to Map<String, dynamic> assignments
      final int mapAssignments = lines
          .where(
            (line) => line.contains("can't be assigned to the parameter type 'Map<String, dynamic>'"),
          )
          .length;

      // Category 2: Dynamic to primitive type assignments (int, String, bool, num)
      final int intAssignments = lines
          .where(
            (line) => line.contains("can't be assigned to the parameter type 'int"),
          )
          .length;
      final int stringAssignments = lines
          .where(
            (line) => line.contains("can't be assigned to the parameter type 'String"),
          )
          .length;
      final int boolAssignments = lines
          .where(
            (line) => line.contains("can't be assigned to the parameter type 'bool"),
          )
          .length;

      // Category 3: Lambda parameter type inference failures
      final int lambdaInference = lines
          .where(
            (line) => line.contains('inference_failure_on_untyped_parameter'),
          )
          .length;

      // Category 4: Function return type inference failures
      final int functionInference = lines
          .where(
            (line) => line.contains('inference_failure_on_function_return_type'),
          )
          .length;

      // Category 5: Variable type inference failures
      final int variableInference = lines
          .where(
            (line) => line.contains('inference_failure_on_uninitialized_variable'),
          )
          .length;

      print('\n=== VIOLATION CATEGORIES ===');
      print('Dynamic to Map<String, dynamic>: $mapAssignments');
      print('Dynamic to int: $intAssignments');
      print('Dynamic to String: $stringAssignments');
      print('Dynamic to bool: $boolAssignments');
      print('Lambda parameter inference: $lambdaInference');
      print('Function return type inference: $functionInference');
      print('Variable type inference: $variableInference');
      print('=== END CATEGORIES ===\n');

      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });
}
