def pytest_configure(config):
    config.addinivalue_line(
        "markers", "requires_pack: needs locally generated packs/<id>/data")
