import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Walks every `.dart` file under `lib/`, finds `State<...>` /
/// `ConsumerState<...>` classes that own disposable resources, and asserts
/// each resource is released in `dispose()`.
///
/// This catches the single most common Flutter leak pattern: adding a new
/// `AnimationController` / `TextEditingController` / `FocusNode` / `Timer` /
/// `StreamSubscription` to a widget's State and forgetting to dispose it.
///
/// It is a textual audit — it does not parse Dart ASTs — so the rule is
/// deliberately strict: if `dispose()` does not mention the field name, the
/// test fails. If a field truly does not need explicit disposal, add it to
/// [_allowedFields] below with a comment explaining why.
void main() {
  test('every StatefulWidget disposes its controllers, timers, and streams',
      () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'Run this test from the project root.');

    final violations = <String>[];
    var stateClassesScanned = 0;
    var classesWithDisposables = 0;

    for (final file in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      // Strip line comments to avoid "// disposed via X" false positives
      // and block comments for the same reason.
      final stripped = _stripComments(source);
      final stateClasses = _findStateClassBodies(stripped);
      stateClassesScanned += stateClasses.length;

      for (final klass in stateClasses) {
        final fields = _findDisposableFields(klass.body);
        if (fields.isEmpty) continue;
        classesWithDisposables++;

        final disposeBody = _extractMethodBody(klass.body, 'dispose');
        if (disposeBody == null) {
          violations.add(
            '${file.path}: class ${klass.name} owns '
            '${fields.map((f) => f.name).join(', ')} '
            'but has no dispose() method.',
          );
          continue;
        }

        for (final field in fields) {
          if (_allowedFields.contains('${klass.name}.${field.name}')) continue;
          if (!disposeBody.contains(field.name)) {
            violations.add(
              '${file.path}: class ${klass.name} '
              'declares ${field.type} ${field.name} but dispose() does not '
              'reference it.',
            );
          }
        }
      }
    }

    // Sanity-check: if the regex finds zero classes, the test is a no-op
    // and is lying about coverage. The repo has >20 State classes today.
    expect(stateClassesScanned, greaterThan(10),
        reason: 'Audit regex did not find State classes — it is broken.');
    expect(classesWithDisposables, greaterThan(3),
        reason: 'Audit regex did not find disposable fields — it is broken.');

    expect(
      violations,
      isEmpty,
      reason:
          'Disposable fields missing from dispose():\n${violations.join('\n')}',
    );
  });
}

/// Field names that are intentionally not disposed in their owning State's
/// dispose() (e.g., disposed via a mixin or handed off to another owner).
/// Keep this list small and comment each entry.
const _allowedFields = <String>{
  // (empty — add entries in the form 'ClassName.fieldName' with a comment)
};

final _disposableTypes = <String>[
  'AnimationController',
  'TextEditingController',
  'FocusNode',
  'ScrollController',
  'PageController',
  'TabController',
  'Timer',
  'StreamSubscription',
  'StreamController',
];

class _StateClass {
  _StateClass(this.name, this.body);
  final String name;
  final String body;
}

class _Field {
  _Field(this.type, this.name);
  final String type;
  final String name;
}

String _stripComments(String source) {
  // Remove // line comments
  var out = source.replaceAll(RegExp(r'//[^\n]*'), '');
  // Remove /* block comments */
  out = out.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return out;
}

List<_StateClass> _findStateClassBodies(String source) {
  final results = <_StateClass>[];
  final classRe = RegExp(
    r'class\s+(\w+)[^{]*extends\s+(?:State|ConsumerState)\s*<[^>]+>[^{]*\{',
  );
  for (final match in classRe.allMatches(source)) {
    final name = match.group(1)!;
    final bodyStart = match.end - 1; // at opening {
    final bodyEnd = _matchBrace(source, bodyStart);
    if (bodyEnd == -1) continue;
    final body = source.substring(bodyStart + 1, bodyEnd);
    results.add(_StateClass(name, body));
  }
  return results;
}

/// Returns the index of the `}` that matches the `{` at [openIdx],
/// or -1 if unbalanced.
int _matchBrace(String source, int openIdx) {
  var depth = 0;
  for (var i = openIdx; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

List<_Field> _findDisposableFields(String classBody) {
  final typeAlt = _disposableTypes.join('|');
  // Matches: [late] [final] Type[<...>][?] name [= ... | ;]
  // We only look at the class body's top level (nested braces break this
  // slightly, but Dart field declarations don't appear inside methods except
  // as locals, which we filter out by requiring start-of-line or brace).
  final fieldRe = RegExp(
    r'(?:^|[;{}\n])\s*(?:late\s+)?(?:final\s+)?(' +
        typeAlt +
        r')(?:<[^>]*>)?\??\s+(\w+)\s*[;=]',
    multiLine: true,
  );
  final seen = <String>{};
  final results = <_Field>[];
  for (final m in fieldRe.allMatches(classBody)) {
    final type = m.group(1)!;
    final name = m.group(2)!;
    // Skip obvious locals inside methods by rejecting names that look like
    // loop variables. The regex already anchors at line/brace start so this
    // is mostly covered.
    if (name == 'dispose' || name == 'build') continue;
    final key = '$type.$name';
    if (seen.add(key)) {
      results.add(_Field(type, name));
    }
  }
  return results;
}

/// Extracts the body of `methodName()` from [classBody], or `null` if absent.
String? _extractMethodBody(String classBody, String methodName) {
  // Match `void methodName()` or `@override ... void methodName()` opening.
  final methodRe = RegExp(
    r'(?:^|[;}\n])\s*(?:@\w+\s+)*(?:Future<[^>]*>|void|\w+)\s+' +
        RegExp.escape(methodName) +
        r'\s*\([^)]*\)\s*(?:async\s*)?\{',
    multiLine: true,
  );
  final match = methodRe.firstMatch(classBody);
  if (match == null) return null;
  final bodyStart = match.end - 1;
  final bodyEnd = _matchBrace(classBody, bodyStart);
  if (bodyEnd == -1) return null;
  return classBody.substring(bodyStart + 1, bodyEnd);
}
