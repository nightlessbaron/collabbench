from collabbench.harness.budget import Budget


def test_budget_warns_once_then_exhausts():
    b = Budget(100)
    assert b.charge(85) == "warn"  # 15 left: less than three calls of this size
    assert b.charge(1) == "ok"
    assert b.charge(20) == "exhausted"
    assert b.used == 106 and b.exhausted


def test_warns_when_three_calls_no_longer_fit():
    b = Budget(1000)
    assert b.charge(100) == "ok"  # 900 left, three calls need 300
    assert b.charge(450) == "warn"  # 450 left, three calls of 450 need 1350
    assert b.charge(10) == "ok"


def test_small_calls_warn_at_ten_percent():
    b = Budget(1000)
    states = [b.charge(10) for _ in range(95)]
    assert states.index("warn") == 90  # the call that leaves less than 100 (10%)
    assert states.count("warn") == 1


def test_turns_left_estimate():
    b = Budget(1000)
    b.charge(400)
    assert b.turns_left(200) == 3


def test_budget_jump_past_limit_is_exhausted_not_warn():
    b = Budget(100)
    assert b.charge(150) == "exhausted"
