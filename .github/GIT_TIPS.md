# Git Tips for Large Commits

## GitHub Warning: "Large Commits have some content hidden"

This warning appears when a commit contains many files or large files. Here's how to handle it:

### ✅ What We've Done

1. **Enhanced `.gitignore`** to exclude:
   - All data directories (`/data`, `/plots`)
   - Binary files (`.jld2`, `.h5`, `.png`, etc.)
   - Large archive files
   - Log files

2. **Organized repository** to reduce file count in commits

### 📋 Best Practices

#### Before Committing

1. **Check what you're committing:**
   ```bash
   git status
   git diff --stat
   ```

2. **Verify large files are ignored:**
   ```bash
   git ls-files | grep -E "\.(jld2|png|jpg)$"
   # Should return nothing if properly ignored
   ```

3. **Split large commits:**
   - Commit documentation changes separately
   - Commit code changes separately
   - Commit configuration changes separately

#### If You Need to Track Large Files

Use **Git LFS** (Large File Storage):
```bash
git lfs install
git lfs track "*.jld2"
git lfs track "*.png"
git add .gitattributes
```

### 🔧 Cleaning Up Existing Commits

If you've already committed large files:

1. **Remove from tracking (keep local files):**
   ```bash
   git rm --cached data/*.jld2
   git rm --cached plots/*.png
   ```

2. **Update .gitignore** (already done)

3. **Commit the cleanup:**
   ```bash
   git add .gitignore
   git commit -m "Remove large files from tracking"
   ```

4. **For historical cleanup** (advanced):
   ```bash
   # Use git filter-repo (install first)
   git filter-repo --path-glob '*.jld2' --invert-paths
   git filter-repo --path-glob '*.png' --invert-paths
   ```

### ⚠️ Important Notes

- **Never commit:**
  - Data files (`.jld2`, `.h5`, etc.)
  - Generated plots (`.png`, `.jpg`, etc.)
  - Large binary files
  - Log files

- **Always commit:**
  - Source code (`.jl`, `.py`, `.sh`)
  - Configuration files (`.toml`, `.yml`)
  - Documentation (`.md`)
  - Small test data if needed

### 📊 Current Status

- ✅ `.gitignore` properly configured
- ✅ Data and plots directories ignored
- ✅ Binary file extensions ignored
- ✅ Repository organized for smaller commits

