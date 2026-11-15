from collabbench.harness.budget import Budget


def test_budget_warns_once_then_exhausts():
    b = Budget(100)
    assert b.charge(85) == "ok"
    assert b.charge(10) == "warn"
    assert b.charge(1) == "ok"
    assert b.charge(10) == "exhausted"
    assert b.used == 106 and b.exhausted


def test_budget_jump_past_limit_is_exhausted_not_warn():
    b = Budget(100)
    assert b.charge(150) == "exhausted"
