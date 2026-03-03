from setuptools import find_packages, setup

setup(
    name="git-forge-release-migrator",
    version="0.1.0",
    description="Provider-based migration tool for releases/tags across Git forges",
    package_dir={"": "src"},
    packages=find_packages(where="src", include=["git_forge_release_migrator*"]),
    python_requires=">=3.9",
)
