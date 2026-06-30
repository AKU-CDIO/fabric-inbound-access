# UZIMA Data Access — Researcher Guide

## One-time setup (admin does this)

1. Sets up the token broker in Azure
2. Adds your email to the approved list
3. Sets `FABRIC_WEBHOOK_URL` on the VM (system environment variable)
4. Gives you the VM login details

That's it. After that, you just log in and use R or Python.

## Daily use

### Step 1: Connect to the VM

Open **Remote Desktop Connection**. Enter the VM address and credentials.

### Step 2: Set your email (first time only)

Open a command prompt and run:

```
setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu
```

Then restart any open R/Python sessions. You only need to do this once — it's saved permanently.

### Step 3: Use R or Python as normal

**In R:**
```r
library(fabriconnect)
conn <- connect_to_fabric()
list_tables(conn)
df <- read_table(conn, "dimenrolledparticipants")
```

**In Python:**
```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
lh.list_tables()
df = lh.to_pandas("dimenrolledparticipants")
```

The first call will automatically contact the auth service with your email and get a token. No browser sign-in, no codes to copy, no separate login step.

### Step 4: When you're done

Just close the window. The connection closes automatically.

## If you haven't set your email

If `FABRIC_RESEARCHER_EMAIL` is not set, the package will detect it's running on the VM and prompt:

```
Email required for data access.
Enter your email:
```

Type your email and press Enter. For convenience, set it permanently with `setx FABRIC_RESEARCHER_EMAIL ...` as shown above.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **"Access denied"** | Your email isn't approved. Contact the admin. |
| **"Auth service error"** | Webhook URL not set on this VM. Contact the admin. |
| **Token expired** | The package auto-refreshes, but if it fails, just reconnect. |
| **"Not on approved VM"** | You're on the wrong computer. Use RDP to the correct VM. |

## Tips

- Read only columns you need: `read_table(conn, "tablename", columns = c("col1", "col2"))`
- List available lakehouses: `connect_to_fabric(lakehouse = "HCW_fitbit_data")`
- Never share your VM login or token with anyone.
