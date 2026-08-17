# Devvy for VS Code

Devvy publishes privacy-safe VS Code editor metadata to the existing local Devvy
daemon at `127.0.0.1:17377`. It never connects to Discord directly.

Install the daemon before installing this extension. For development/testing,
package with `npm run package`, then use **Extensions: Install from VSIX...**.
The Marketplace publisher must be created and verified before public release.
