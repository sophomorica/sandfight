import 'dart:math' as math;

class SandGrid {
  SandGrid() : cells = List<int>.filled(cols * rows, 0);

  static const cols = 12;
  static const rows = 20;
  static const cellMax = 15;

  final List<int> cells;

  factory SandGrid.pile(int mass) {
    final grid = SandGrid();
    grid.addBottom(mass);
    return grid;
  }

  factory SandGrid.fromCells(List<int> source) {
    final grid = SandGrid();
    for (var i = 0; i < grid.cells.length; i++) {
      grid.cells[i] = source[i];
    }
    return grid;
  }

  int cell(int col, int row) => cells[row * cols + col];

  int get mass => cells.fold(0, (sum, value) => sum + value);

  void addBottom(int amount) {
    var left = amount;
    var row = rows - 1;
    while (left > 0 && row >= 0) {
      var placed = false;
      for (var col = 0; col < cols && left > 0; col++) {
        final index = row * cols + col;
        if (cells[index] >= cellMax) continue;
        cells[index] += 1;
        left -= 1;
        placed = true;
      }
      if (!placed) row -= 1;
    }
    if (left > 0) {
      throw StateError('grid cannot hold $left more mass');
    }
  }

  int takeNear(double nx, double ny, int want) {
    if (want <= 0) return 0;
    final col = (nx.clamp(0.0, 1.0) * (cols - 1)).round();
    final row = (ny.clamp(0.0, 1.0) * (rows - 1)).round();
    final order = List<int>.generate(cells.length, (index) => index);
    order.sort((a, b) {
      final da = _dist2(a, col, row);
      final db = _dist2(b, col, row);
      return da.compareTo(db);
    });
    var got = 0;
    for (final index in order) {
      if (got >= want) break;
      final n = math.min(cells[index], want - got);
      cells[index] -= n;
      got += n;
    }
    return got;
  }

  int _dist2(int index, int col, int row) {
    final c = index % cols;
    final r = index ~/ cols;
    final dc = c - col;
    final dr = r - row;
    return dc * dc + dr * dr;
  }
}
