# Step-by-step guide: finding the OCI values used by the script

This guide shows where to find the values required by the local .env file in the Oracle Cloud Console. The screenshots are UI examples only: real tenancy names, user data, OCIDs, fingerprints, and network values are covered with black redaction boxes.

Copy values into the private .env file on your computer or server. Do not put them in README files, screenshots, public issues, or GitHub commits.

## First: what do the basic terms mean?

If you are new to development or cloud platforms, these definitions are enough:

| Term | Simple explanation |
| --- | --- |
| Tenancy | Your Oracle Cloud account and its complete cloud environment |
| Compartment | A folder inside the account that contains resources |
| Region | An Oracle geographic location, such as a city or country |
| Availability domain (AD) | One physical zone inside a region |
| VCN | A private network for your cloud servers |
| Subnet | A smaller network inside the VCN where a server is placed |
| Image | The operating system installed on the server |
| Shape | The server size: CPU and memory |
| OCID | A long, unique ID for an Oracle resource |
| API key | A credential that lets the script authenticate to OCI |
| SSH public key | The public half of the key used to connect to the server over SSH |

The .env file is a private configuration file. It stores values without changing the source code. Replace every placeholder such as <something> with your own value; do not type the angle brackets.

## Quick order for beginners

Follow these steps in order:

1. Create .env from the template.
2. Select the correct region in the OCI Console.
3. Find the root compartment OCID and put it in COMPARTMENT_ID.
4. Create or verify an API key and OCI config file.
5. Find the availability domains and put them in ADS.
6. Find a subnet; the simplest option is to set SUBNET_ID.
7. Leave IMAGE_ID empty so the script can find a suitable image automatically.
8. Confirm the shape is A1 with 2 OCPU and 12 GB of memory.
9. Run a dry run. Start the real retry process only after the dry run succeeds.

You do not need to understand every CLI command immediately. The commands are optional helpers; the same values can be found by clicking through the Console.

## Step 1 – create a private .env file

1. Open the OCI Console and select the region from the top Region menu.
2. Use the same region where you want to run the A1 instance.
3. Create the local configuration file:

~~~bash
cp .env.example .env
chmod 600 .env
~~~

The current script expects COMPARTMENT_ID to be the root compartment/tenancy OCID. It uses that value both for tenancy validation and as the target compartment. If you want to use a child compartment, the code should first be extended with a separate TENANCY_ID setting.

Each .env setting uses one line. For example, OCPUS=2 means that the requested CPU count is 2. Do not add spaces around the equals sign.

## Step 2 – find the tenancy, compartment, and region

### TENANCY_NAME

This is only a readable name used in logs; it does not grant access. You can read it from User menu → Tenancy or from the root compartment row.

### COMPARTMENT_ID

1. Open Identity & Security → Compartments.
2. Find the row marked as the root compartment, usually shown as the tenancy name followed by (root).
3. Open the row details or scroll the table horizontally to the OCID column.
4. Copy the complete OCID into the local .env as COMPARTMENT_ID.

![Masked OCI Compartments screen](docs/screenshots/01-compartments.png)

Optional read-only CLI command for listing child compartments:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  iam compartment list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --output table
~~~

### REGION

In the top Region menu, copy the region key, not only the display name of the city. Put a value shaped like <region-key> in .env.

If the Console is open in a different region, the VCN, subnet, image, and availability domains may be different or unavailable.

## Step 3 – find availability domains and the A1 size

### ADS

Using the Console:

1. Open Compute → Instances → Create instance.
2. In the Placement section, review all availability domains.
3. For ADS, use the full OCI availability-domain names, not only the short labels AD 1, AD 2, or AD 3.
4. Separate the values with commas:

~~~dotenv
ADS=<availability-domain-1>,<availability-domain-2>,<availability-domain-3>
~~~

The most reliable way to get the full names is the CLI:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  iam availability-domain list \
  --compartment-id "$COMPARTMENT_ID" \
  --output json
~~~

If an AD repeatedly returns OUT_OF_HOST_CAPACITY, it can remain in the list. If it does not exist in the selected region or cannot be used by the account, remove it from ADS.

### SHAPE, OCPUS, and MEMORY_GB

In the same Create instance form:

1. Click Change shape.
2. Select Ampere.
3. Select VM.Standard.A1.Flex.
4. Set 2 OCPU and 12 GB of memory.

![Masked OCI Create compute instance screen](docs/screenshots/04-create-instance.png)

For the requested target, the .env values should be:

~~~dotenv
SHAPE=VM.Standard.A1.Flex
OCPUS=2
MEMORY_GB=12
TOTAL_OCPU_LIMIT=2
TOTAL_MEMORY_LIMIT=12
~~~

The TOTAL_* values protect against creating extra instances. The script stops when the combined A1 usage reaches the configured limit.

## Step 4 – find the network and subnet

### VCN_NAME and VCN ID

1. Open Networking → Virtual cloud networks.
2. Select a VCN in the correct compartment.
3. On the VCN details page, copy the full resource OCID if you need it for manual administration.

![Masked OCI VCN list screen](docs/screenshots/02-vcn.png)

Optional read-only CLI command:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  network vcn list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --output table
~~~

VCN_NAME, GATEWAY_NAME, and SECURITY_LIST_NAME are used by bootstrap_oci_network.sh to create or find network resources. VCN ID is not a required .env variable.

### SUBNET_ID and SUBNET_NAME

1. On the VCN details page, open the Subnets tab.
2. Select a subnet with the correct CIDR and access type, such as a public subnet if the instance needs a public IP address.
3. Copy the complete subnet OCID into SUBNET_ID.
4. If you leave SUBNET_ID empty, set the exact display name in SUBNET_NAME; the script will find the subnet by name.

![Masked OCI Subnets screen](docs/screenshots/03-subnets.png)

Optional CLI command for viewing subnet IDs:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  network subnet list \
  --compartment-id "$COMPARTMENT_ID" \
  --all \
  --output table
~~~

If you use bootstrap_oci_network.sh, it prints VCN_ID and SUBNET_ID at the end. Keep those values in local configuration only; do not copy them into GitHub documentation.

## Step 5 – choose the operating system image

### Recommended: leave IMAGE_ID empty

The main script automatically finds the newest available image using these settings:

~~~dotenv
IMAGE_ID=
IMAGE_OS="Oracle Linux"
IMAGE_OS_VERSION=9
~~~

The same choice is visible in the Console through Create instance → Change image → Oracle Linux → Oracle Linux 9.

![Masked OCI image selector](docs/screenshots/07-image-selector.png)

### Fixed IMAGE_ID

If you want to pin one exact image, list the available images with the CLI:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  compute image list \
  --compartment-id "$COMPARTMENT_ID" \
  --operating-system "$IMAGE_OS" \
  --operating-system-version "$IMAGE_OS_VERSION" \
  --shape "$SHAPE" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --all \
  --output json
~~~

In the JSON output, choose an image whose lifecycle state is AVAILABLE and put its ID only in the local .env:

~~~dotenv
IMAGE_ID=<image-resource-ocid>
~~~

If you leave IMAGE_ID empty, the repository code performs the same lookup automatically.

## Step 6 – give the script access to the OCI account

These values do not come from the instance creation form.

### User OCID

1. Open User menu → User settings.
2. On My profile, stay on the Details tab.
3. In User information, find the OCID row.

![Masked OCI user profile screen](docs/screenshots/05-user-profile.png)

The user OCID is not the same as the tenancy or compartment OCID. Do not swap them.

### API key and fingerprint

1. On the same page, open Tokens and keys.
2. In API keys, click Add API key only if there is no existing key you can use.
3. Download the private key and store it outside the repository.
4. The displayed fingerprint must match the key in the OCI config file.

![Masked OCI API keys screen](docs/screenshots/06-api-keys.png)

A typical OCI CLI profile looks like this. Replace the placeholders locally; never put real values in this guide or a commit:

~~~ini
[DEFAULT]
user=<user-ocid>
tenancy=<tenancy-ocid>
region=<region-key>
fingerprint=<api-key-fingerprint>
key_file=/secure/path/private-key.pem
~~~

Do not copy the private key into .env. OCI_CONFIG_FILE is only the path to the private OCI config file, while OCI_PROFILE is the profile name:

~~~dotenv
OCI_CONFIG_FILE=/secure/path/to/oci/config
OCI_PROFILE=DEFAULT
~~~

To verify the profile without printing the key contents:

~~~bash
oci --config-file "$OCI_CONFIG_FILE" \
  --profile "$OCI_PROFILE" \
  --region "$REGION" \
  iam tenancy get \
  --tenancy-id "$COMPARTMENT_ID" \
  --query 'data.name' \
  --raw-output
~~~

## Step 7 – prepare the SSH public key

SSH_KEY_FILE is not an OCI ID. It is the path to the public SSH key sent to the instance.

If you do not already have a dedicated key, create one locally:

~~~bash
ssh-keygen -t ed25519 -f ~/.ssh/oci-a1 -C oci-a1
~~~

Put only the .pub file in .env:

~~~dotenv
SSH_KEY_FILE=/secure/path/.ssh/oci-a1.pub
~~~

Never put the private file without the .pub suffix into the repository or a public upload.

## Step 8 – fill in the remaining settings

| Variable | How it is chosen |
| --- | --- |
| DISPLAY_NAME | Any readable instance name |
| ASSIGN_PUBLIC_IP | Network setting; use true if the instance needs a public IP |
| SSH_SOURCE_CIDR | Your public IP in /32 format or a VPN CIDR; used by the network helper |
| VCN_CIDR_BLOCK / SUBNET_CIDR_BLOCK | Private network ranges you want to use |
| SLEEP_SECONDS | Initial retry-cycle delay; this configuration uses 30 seconds |
| MAX_RETRY_DELAY_SECONDS | Maximum retry delay; this configuration uses 180 seconds |
| CAPACITY_REQUEST_DELAY_SECONDS | Delay between capacity API calls |
| NETWORK_RECHECK_DELAYS | Delays used after an uncertain network error |
| LOCK_FILE | Local path to the lock file |

## Step 9 – verify the configuration before running

Check only that important keys exist, without printing their values:

~~~bash
for key in TENANCY_NAME COMPARTMENT_ID REGION OCI_CONFIG_FILE OCI_PROFILE \
  SHAPE OCPUS MEMORY_GB ADS SSH_KEY_FILE; do
  if grep -q "^$key=" .env; then
    echo "$key: set"
  else
    echo "$key: MISSING"
  fi
done
~~~

Then run the read-only checks:

~~~bash
DRY_RUN=1 ./oci_capacity_retry.sh
python3 oracle_free_tier_checker.py --json
~~~

Before committing, verify that .env, the OCI config, private keys, server connection strings, and logs are not tracked:

~~~bash
git status --ignored
git ls-files
~~~

The repository should remain private until its full Git history has been reviewed for secrets.
