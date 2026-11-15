"""Brief-only decision F3 (CollabBench)."""


def test_F3_mapi_settings_ignore_unknown():
    from emmet.api.core.settings import MAPISettings

    settings = MAPISettings(not_a_setting=1)
    assert not hasattr(settings, "not_a_setting")
