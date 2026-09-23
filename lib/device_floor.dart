bool meetsIphone12(String machine) {
  final match = RegExp(r'^iPhone(\d+),').firstMatch(machine);
  if (match == null) return true;
  return int.parse(match.group(1)!) >= 13;
}
