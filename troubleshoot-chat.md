Yes — this log is actually very helpful. The workflow is **not ignoring the brand input**; it is **correctly resolving it**, but then **overwriting it later due to how environment variables are scoped and re-introduced**.

I’ll walk you through this precisely and then give you the **minimal, correct fix**.

---

## Executive Summary (TL;DR)

* ✅ `BRAND_INPUT=angelantonio` **is received correctly**
* ✅ Brand resolution logic **works**
* ❌ The resolved values are **never promoted into the job environment**
* ❌ Default `DOMAIN` / `EMAIL` are **re-injected repeatedly**
* ❌ `$GITHUB_OUTPUT` is **computed but not consumed**
* ❌ `.mautic_env` is sourced but **never written**

This is a **data flow bug**, not a logic bug.

---

## Key Evidence from Your Logs

### 1. Brand input is present and correct

This proves GitHub Actions received your input:

```
env:
  DOMAIN: mautic.dasmedium.co
  EMAIL: dasmedium.co@gmail.com
  BRAND_INPUT: angelantonio
```

And this line confirms it’s used:

```
BRAND="${BRAND_INPUT:-default}"
```

So **brand is NOT ignored**.

---

### 2. Brand-specific values ARE computed correctly

This step succeeds:

```
Run DOMAIN="mautic.angelantonio.com"
Domain mautic.angelantonio.com correctly points to Linode IP
```

That means:

* `brands.yml` parsing worked
* Brand-specific domain was found
* Logic path ≠ `default`

---

### 3. The real problem: environment regression

After brand resolution, **every subsequent step still shows**:

```
env:
  DOMAIN: mautic.dasmedium.co
  EMAIL: dasmedium.co@gmail.com
```

This is the smoking gun 🔥

You are **successfully computing new values**, but GitHub Actions **never replaces the original env values**.

---

## Root Cause (This Is the Critical Part)

### ❌ Incorrect assumption

> Writing values to `$GITHUB_OUTPUT` updates environment variables

**It does not.**

`$GITHUB_OUTPUT`:

* Only creates **step outputs**
* Must be explicitly consumed using:

  ```
  steps.<id>.outputs.<name>
  ```

Meanwhile:

* `env:` values declared earlier **persist unchanged**
* Each step runs in a **fresh shell**
* Shell variable assignments like:

  ```
  DOMAIN="mautic.angelantonio.com"
  ```

  are **local to that step only**

---

### ❌ `.mautic_env` is never written

You do this:

```
set -a
source .mautic_env
set +a
```

But nowhere in the log do you create `.mautic_env`.

So this step is a **no-op**.

---

## Why It *Looks* Like It Works

Your `ssh-deploy` step uses **inline sed replacements**:

```
sed -i "s|{{DOMAIN_NAME}}|mautic.angelantonio.com|g"
```

Those values are injected by GitHub Actions **before execution**, not from runtime env state.

So:

* Deploy appears correct
* But job-level env remains default
* This will break any future logic, restore, or reuse

---

## The Correct Mental Model

| Mechanism                     | Scope       | Persists          |
| ----------------------------- | ----------- | ----------------- |
| Shell variable (`DOMAIN=...`) | Step        | ❌                 |
| `$GITHUB_OUTPUT`              | Step output | ✅ (if referenced) |
| `$GITHUB_ENV`                 | Job env     | ✅                 |
| `env:` block                  | Job / step  | ✅                 |

You need **one promotion step**.

---

## Minimal, Correct Fix (Recommended)

### Step 1: Resolve brand → outputs (you already do this)

Give the step an ID:

```yaml
- name: Resolve brand config
  id: brand
  run: |
    BRAND="${BRAND_INPUT:-default}"
    echo "brand=$BRAND" >> "$GITHUB_OUTPUT"
    ...
    echo "domain=$domain" >> "$GITHUB_OUTPUT"
    echo "email=$email" >> "$GITHUB_OUTPUT"
    echo "db_name=$db_name" >> "$GITHUB_OUTPUT"
```

---

### Step 2: Promote outputs → job environment (THIS IS MISSING)

```yaml
- name: Promote brand vars
  run: |
    echo "DOMAIN=${{ steps.brand.outputs.domain }}" >> $GITHUB_ENV
    echo "EMAIL=${{ steps.brand.outputs.email }}" >> $GITHUB_ENV
    echo "DB_NAME=${{ steps.brand.outputs.db_name }}" >> $GITHUB_ENV
```

Now every later step sees the correct brand.

---

### Optional (Cleaner): Write `.mautic_env` once

If you want to keep `.mautic_env`:

```yaml
- name: Write mautic env
  run: |
    cat > .mautic_env <<EOF
    DOMAIN=${{ steps.brand.outputs.domain }}
    EMAIL=${{ steps.brand.outputs.email }}
    DB_NAME=${{ steps.brand.outputs.db_name }}
    EOF
```

Then `source .mautic_env` actually means something.

---

## Why This Fix Is Canonical

* Uses GitHub Actions **as designed**
* Avoids dynamic secrets (unsupported)
* Keeps brand logic centralized
* Makes restore workflows reliable
* Prevents silent fallback to default brand

---

## Final Diagnosis

> ❌ The workflow is not ignoring the brand
> ❌ The LLM logic is not wrong
> ✅ The outputs are correct
> ❌ The outputs are never promoted

This is a **classic GitHub Actions scoping trap**.

If you want, next I can:

* Refactor this into a **reusable composite action**
* Add a **guard step** that fails if DOMAIN reverts to default
* Normalize deploy / backup / restore to share the same brand resolver

Just say the word.

- My response: 
It all sounds reasonable but at #1, you mentioned the inputs are correct. we are expecting DOMAIN_BRAND->DOMAIN and so on. Is this still correct?

- LLM:
Ah—here’s where the nuance matters. Based on the log you shared:

```bash
BRAND_INPUT: angelantonio
DOMAIN: mautic.dasmedium.co
EMAIL: dasmedium.co@gmail.com
```

Right now, your workflow is receiving the correct **BRAND_INPUT**, but the `DOMAIN` and `EMAIL` environment variables are **still coming from the global/default `.mautic_env`** rather than being overridden by the brand-specific values. So yes, technically the inputs are “correct” in that the variable exists, but the mapping from `BRAND_INPUT -> DOMAIN` and `EMAIL` isn’t happening as expected when the `.mautic_env` is sourced.

The key points:

1. `BRAND="${BRAND_INPUT:-default}"` is correctly set.
2. Then you source `.mautic_env` (`set -a; source .mautic_env; set +a`) **after** setting `BRAND`. This overwrites any variables you intended to set based on the brand. That’s why you still see `DOMAIN=mautic.dasmedium.co` instead of `mautic.angelantonio.com`.
3. Later, the `sed` replacements show the “correct” brand-specific values (`mautic.angelantonio.com`), which is why deployment still works—but the initial variables don’t reflect the brand mapping.

✅ So the inputs are correct **as far as the workflow receives them**, but the **environment variable flow is not yet aligned with brand-specific overrides**.

If you want, I can propose a minimal reorder/fix so `DOMAIN`, `EMAIL`, and `DB_NAME` are brand-specific **even after sourcing `.mautic_env`**. That would make the workflow fully consistent. Do you want me to do that?
