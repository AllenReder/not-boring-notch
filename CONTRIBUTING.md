# Contributing

Thank you for taking the time to contribute! ❤️

These guidelines help streamline the contribution process for everyone involved. By following them, you'll make it easier for maintainers to review your work and collaborate with you effectively.

You can contribute in many ways: writing code, improving documentation, reporting bugs, requesting features, or creating tutorials and blog posts. Every contribution, large or small, helps make Not Boring Notch better.

## Table of Contents

- [Localizations](#localizations)
- [Contributing Code](#contributing-code)
  - [Before You Start](#before-you-start)
  - [Setting Up Your Environment](#setting-up-your-environment)
  - [Making Changes](#making-changes)
  - [Pull Requests](#pull-requests)
<!-- - [Code Style Guidelines](#code-style-guidelines) -->
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Getting Help](#getting-help)

## Localizations

The interface is localized through `NotBoringNotch/Localizable.xcstrings`. New strings are
added in English, and translation updates are welcome as pull requests that edit that file
directly. This project does not use Crowdin.

## Contributing Code

### Before You Start

- **Check existing issues**: Before creating a new issue or starting work, search existing issues to avoid duplicates.
- **Discuss major changes**: For significant features or major changes, please open an issue first to discuss your approach with maintainers and the community.
<!-- - **Review the code style**: Familiarize yourself with our code style guidelines below to ensure consistency. -->

> [!IMPORTANT]
> All contributions are based on `main`. Create a short-lived branch off `main` and open your pull request against `main`.

### Setting Up Your Environment

1. **Fork the repository**: Click the "Fork" button at the top of the repository page to create your own copy. Maintainers work on branches in this repository directly.

2. **Clone your fork**:
   ```bash
   git clone https://github.com/{your-username}/not-boring-notch.git
   cd not-boring-notch
   ```
   Replace `{your-username}` with your GitHub username.

3. **Update `main`**:
   ```bash
   git checkout main
   git pull
   ```

4. **Create a new branch**:
   ```bash
   git checkout -b feature/{your-feature-name}
   ```
   Replace `{your-feature-name}` with a descriptive name. Use lowercase letters, numbers, and hyphens only (e.g., `feature/add-dark-mode` or `fix/notification-crash`).

### Making Changes

1. **Make your changes**: Implement your feature or bug fix. Write clean, well-documented code <!-- following the project's style guidelines. -->

2. **Test your changes**:
   ```bash
   ./scripts/run-tests.sh      # the standalone runners in Tests/
   ./scripts/check-branding.sh # fails if the old boringNotch name has crept back in
   ./scripts/check-version.sh  # fails if the project's version settings disagree
   ```
   CI blocks on all three, so run them before you push — each is a grep or a few seconds of
   `swiftc`, and the third one exists because a version bumped in only some of its four copies
   is not a build error, just a lie the app tells about itself.

3. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add descriptive commit message"
   ```
   Write clear, concise commit messages that explain what your changes do and why.

4. **Keep your branch up to date**:
   Regularly sync your branch with the latest changes from `main` to avoid conflicts.

5. **Push to your fork**:
   ```bash
   git push origin feature/{your-feature-name}
   ```

### Pull Requests

1. **Create a pull request**: Open a pull request against `main` in this repository, with your branch as the source.

2. **Write a detailed description**: Your PR should include:
   - A clear title summarizing the changes
   - A detailed description of what was changed and why
   - Reference to any related issues (e.g., "Fixes #123" or "Relates to #456")
   - Screenshots or screen recordings for UI changes

3. **Respond to feedback**: Maintainers may request changes.

4. **Be patient**: Reviews take time. Maintainers will get to your PR as soon as they can.

<!-- ## Code Style Guidelines

- Follow the existing code style and conventions used in the project
- Write clear, self-documenting code with meaningful variable and function names
- Add comments for complex logic or non-obvious implementations
- Ensure your code is properly formatted before committing
- Remove any debugging code, console logs, or commented-out code before submitting -->

## Reporting Bugs

When reporting bugs, please include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Screenshots or error messages if applicable
- Your environment details (OS version, app version, etc.)

## Feature Requests

Feature requests are welcome! Please:

- Check if the feature has already been requested
- Clearly describe the feature and its use case
- Explain why this feature would be valuable to users
- Be open to discussion and alternative approaches

## Getting Help

If you need help or have questions:

- Check the project documentation
- Search existing issues for similar questions
- Open a new issue with the "question" label

---

Thank you for contributing to Not Boring Notch! Your efforts help make this project better for everyone. 🎉
