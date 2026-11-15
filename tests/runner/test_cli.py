import subprocess
import sys

from collabbench.cli import parse_seeds


def test_parse_seeds():
    assert parse_seeds("1-3") == [1, 2, 3] and parse_seeds("2,5") == [2, 5] and parse_seeds("4") == [4]


def test_gen_pool(tmp_path):
    run = subprocess.run([sys.executable, "-m", "collabbench.cli", "gen", "pool", "--seeds", "1-2", "--out",
                          str(tmp_path)], capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    assert sorted(p.name for p in tmp_path.iterdir()) == ["pool-0001", "pool-0002"]
