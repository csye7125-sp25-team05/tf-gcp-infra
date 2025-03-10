# tf-gcp-infra
Terraform setup, workflow, and infrastructure destruction for the `tf-gcp-infra` repository. Test1
---
Test
## **Installation**

### **macOS (Homebrew)**

```
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### **Windows**

1. Download the [64-bit Windows binary](https://developer.hashicorp.com/terraform/downloads) [1][2]
2. Unzip to `C:\Program Files\Terraform`
3. Add Terraform to your system `PATH`:
   - Open **Environment Variables** > Edit `PATH` > Add `C:\Program Files\Terraform`

### **Linux (Ubuntu/Debian)**

```
sudo apt-get update
sudo apt-get install -y gnupg software-properties-common
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
```

Verify installation:

````
terraform -v  # Expected output: "Terraform v1.6.x"

---

## **Getting Started**
1. Clone this repository:
   ```bash
   git clone https://github.com/csye7125-sp25-team05/tf-gcp-infra.git
   cd tf-gcp-infra
````

2. Initialize Terraform in a project directory (e.g., `gcp-project-demo`):
   ```bash
   cd gcp-project-demo
   terraform init
   ```

---

## **Basic Commands**

| Command             | Purpose                                |
| ------------------- | -------------------------------------- |
| `terraform plan`    | Preview infrastructure changes         |
| `terraform apply`   | Deploy infrastructure                  |
| `terraform destroy` | Destroy **all** managed infrastructure |

---

## **Destroying Infrastructure**

### Full Destruction

```bash
terraform destroy  # Removes all resources in the state file
```

- **Example Output**:
  ```
  Plan: 0 to add, 0 to change, 5 to destroy.
  Do you really want to destroy all resources? Enter 'yes'
  ```

### Targeted Destruction

Destroy specific resources (e.g., a GCE instance):

```bash
terraform destroy -target google_compute_instance.example
```

### Automated Destruction (CI/CD)

```bash
terraform destroy -auto-approve  # Skips confirmation
```

### HCP Terraform (Cloud)

1. Navigate to workspace **Settings > Destruction & Deletion**
2. Click **Queue destroy plan** > Confirm

---

## **Best Practices**

1. **Avoid `-auto-approve` in production** – Manual review is critical
2. Use `terraform plan -destroy` to preview deletions
3. Destroy ephemeral environments (dev/staging) regularly
4. **Never** manually delete resources – Update configurations instead

---

## **Related Files**

1. `.gitignore` – Excludes Terraform state files, IDE configs, and OS artifacts
2. GitHub Actions – Pre-merge checks for formatting/validation
