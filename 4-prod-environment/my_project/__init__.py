import importlib

def test_openmm():
    mod = importlib.import_module("openmm.testInstallation")
    if hasattr(mod, "main"):
        mod.main()
    print("Welcome from OpenMM!")