import csv
import tempfile
import unittest
from pathlib import Path

from scope_existing_02c import summarize, EXPECTED_TERMINALS


def write_csv(directory, name, cols, records):
    with (directory / name).open('w', newline='', encoding='utf8') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(records)


class TestLowScope(unittest.TestCase):
    def setup_dataset(self, d):
        write_csv(d, '02C_zero_pointer_cells.csv', ['cell', 'component_id'],
                  [{'cell': a, 'component_id': i+1} for i, a in enumerate(EXPECTED_TERMINALS)])
        write_csv(d, '02C_shore_component_classification.csv',
                  ['component_id', 'connector_status', 'n_zero_cells'],
                  [{'component_id': i+1, 'connector_status': 'INTERIOR_REVIEW', 'n_zero_cells': 1}
                   for i in range(7)])
        write_csv(d, '02F_water_connected_route_evidence.csv',
                  ['route_status', 'terminal_cell'],
                  [{'route_status': 'D8_ZERO_INTERIOR', 'terminal_cell': a} for a in EXPECTED_TERMINALS] +
                  [{'route_status': 'REACHES_RIVER_AREA', 'terminal_cell': '99'}])

    def test_reconciliation(self):
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            self.setup_dataset(d)
            r = summarize(d)
            self.assertEqual(r['02c_zero_cells'], 7)
            self.assertEqual(r['02c_components'], 7)
            self.assertEqual(r['02f_routes'], 8)
            self.assertEqual(r['02f_unique_zero_terminals'], 7)
            self.assertEqual(r['02f_zero_in_02c'], 7)

    def test_inconsistent_component_count_fails_closed(self):
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            self.setup_dataset(d)
            write_csv(d, '02C_shore_component_classification.csv',
                      ['component_id', 'connector_status', 'n_zero_cells'],
                      [{'component_id': i+1, 'connector_status': 'INTERIOR_REVIEW', 'n_zero_cells': 2}
                       for i in range(7)])
            with self.assertRaisesRegex(ValueError, 'count'):
                summarize(d)

    def test_missing_column_fails_closed(self):
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            self.setup_dataset(d)
            write_csv(d, '02F_water_connected_route_evidence.csv', ['bad'], [{'bad': 3}])
            with self.assertRaisesRegex(ValueError, 'columns'):
                summarize(d)

    def test_partial_02c_coverage_is_explicit(self):
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            self.setup_dataset(d)
            write_csv(d, '02C_zero_pointer_cells.csv', ['cell', 'component_id'],
                      [{'cell': a, 'component_id': i+1} for i, a in enumerate(EXPECTED_TERMINALS[:6])])
            write_csv(d, '02C_shore_component_classification.csv',
                      ['component_id', 'connector_status', 'n_zero_cells'],
                      [{'component_id': i+1, 'connector_status': 'INTERIOR_REVIEW', 'n_zero_cells': 1}
                       for i in range(6)])
            r = summarize(d)
            self.assertEqual(r['02f_zero_in_02c'], 6)
            self.assertIsNone(r['known_terminals'][-1]['02c_class'])


if __name__ == '__main__':
    unittest.main()
