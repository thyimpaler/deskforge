# Security

Please report security problems privately through GitHub's private vulnerability reporting
(the repo's Security tab, then "Report a vulnerability"). Do not open a public issue for them.

Useful to include: what you found, the steps to see it, your Windows build, and which deskforge files are involved.

In scope: anything that lets deskforge change a machine without the dry run and a yes, leaves changes that
`tools\restore.ps1` cannot undo, sends data somewhere the docs do not say, or runs code from outside the repo.