# Contributing to cisraeliqueue

Thank you for considering contributing to cisraeliqueue! Here are some guidelines to help you get started:

## Getting Started

1. **Fork the Repository**: Fork the repository to your own GitHub account.

2. **Clone the Repository**: Clone your forked repository to your local machine.
   ```sh
   git clone https://github.com/your-username/cisraeliqueue.git
   ```

3. **Create a Branch**: Create a new branch for your feature or bug fix.
   ```sh
   git checkout -b feature-or-bugfix-name
   ```

## Making Changes

1. **Install Dependencies**: Install the necessary dependencies.
   ```sh
   python -m venv .venv
   source ./.venv/Scripts/activate
   pip install -e '.[dev]'
   ```

2. **Make Changes**: Implement your changes in the codebase.

3. **Recompile Module**: Before running the tests, we need to recompile the cython module.
   ```sh
   pip install -e '.[dev]'
   ```

4. **Run Tests**: Ensure that all tests pass before committing your changes.
   ```sh
   python -m unittest
   mypy src
   ```

5. **Run Formatter**: Format your code to adhere to the project's style guidelines.
   ```sh
   ruff format src tests
   ```

6. **Commit Changes**: Commit your changes with a descriptive commit message.
   ```sh
   git commit -m "Description of the changes made"
   ```

7. **Push Changes**: Push your changes to your forked repository.
   ```sh
   git push origin feature-or-bugfix-name
   ```

## Submitting Changes

1. **Create a Pull Request**: Open a pull request to the main repository. Provide a clear description of the changes and any related issue numbers.

2. **Review Process**: Participate in the review process. Make any requested changes and update the pull request.

3. **Merge**: Once approved, your changes will be merged into the main repository.

## Code Style

- Follow the PEP 8 style guide for Python code.
- Use type hints where appropriate.
- Write clear and concise commit messages.

## Reporting Issues

If you find a bug or have a feature request, please open an issue on GitHub. Provide as much detail as possible to help us understand and address the issue.

Thank you for your contributions!

# For Maintainers

## Merging PRs

1. **Wait for all checks to complete**: These include linters and testing.
2. **Merge with squash**: Change the commit message according to the prefixes set in `cliff.toml`, ending with `(#PR)`. The message should be in markdown format.  
    For example:  
   `feat: My new feature (#12)`  
   or  
   ```
   fix: My bugfix at `cls.__init__`(#45).
   ```

## Bumping Version

1. **Install Dependencies**: Ensure you have `git-cliff` installed.
   ```sh
   pip install git-cliff
   ```

2. **Update Version**: Bump the version in `pyproject.toml`.

3. **Generate Changelog**: Use `git-cliff` to generate the changelog. Replace `x.y.z` with the new version number.
   ```sh
   git cliff --tag x.y.z -o CHANGELOG.md
   ```

4. **Commit Changes**: Commit the updated `CHANGELOG.md` and version changes.
   ```sh
   git add CHANGELOG.md pyproject.toml
   git commit -m "Bump version to x.y.z"
   ```

5. **Tag the Release**: Create a new git tag for the release.
   ```sh
   git tag x.y.z
   git push origin x.y.z
   ```

6. **Push Changes**: Push the changes to the main repository.
   ```sh
   git push origin master
   ```

7. **Create Release**: Go to the GitHub repository and create a new release using the pushed tag. Include the changelog in the release description.

