import 'package:path/path.dart' as p;

List<String> buildRustLibraryCandidates({required String executablePath}) {
  return <String>[
    p.normalize(p.join(p.dirname(executablePath), 'compact_games_core.dll')),
  ];
}
