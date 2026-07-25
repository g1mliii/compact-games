class ManagedRestoreGame {
  const ManagedRestoreGame({
    required this.gamePath,
    required this.gameName,
    required this.drive,
    required this.requiredBytes,
  });

  final String gamePath;
  final String gameName;
  final String drive;
  final int requiredBytes;
}

class ManagedRestoreDrive {
  const ManagedRestoreDrive({
    required this.drive,
    required this.requiredBytes,
    required this.availableBytes,
  });

  final String drive;
  final int requiredBytes;
  final int availableBytes;

  bool get hasEnoughSpace => availableBytes >= requiredBytes;
}

class ManagedRestorePlan {
  const ManagedRestorePlan({required this.games, required this.drives});

  final List<ManagedRestoreGame> games;
  final List<ManagedRestoreDrive> drives;

  int get gameCount => games.length;
  int get requiredBytes =>
      drives.fold(0, (total, drive) => total + drive.requiredBytes);
  bool get hasEnoughSpace => drives.every((drive) => drive.hasEnoughSpace);
}
