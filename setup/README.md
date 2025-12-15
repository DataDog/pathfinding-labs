# Pathfinding Labs Deployment Script

This directory will contain an interactive setup script that will ask the user information about their environment and guide them through the steps needed to get Pathfinding Labs working. 

Here is the outline for the script: 

Ask the user if they have 3 accounts ready to use already


### If you already have 3 accounts that you can use for this lab

* **Step 1:** Configure Pathfinding Labs' terraform.tfvars with the three AWS profiles to use for prod, dev, and ops (the script can ask for the three profiles and grab the account ids when it is testing to see if they all work.)
* **Step 2:** Deploy Pathfinding Labs
* **Step 3:** Run `create_pathfinder_profiles.sh` to create the remaining profiles. 

### If you don't yet have 3 accounts that you can use for this lab

* **Step 1, Option A:** If you don't have anything you consider a production workload in your personal playground/testing account, enable AWS Organizations in this account
* **Step 1, Option B:** If you do have what you consider production workloads in your personal playground/test account, create a new AWS account and enable AWS Organizations in this new account
* **Step 2:** From within the Organization management account, create 3 accounts dedicated for pathfinding-labs pl-prod, pl-dev, pl-ops (creating accounts is free, and they will all roll up their billing to the mgmt account). 
* **Step 4:** Set up AWS IAM Identity Center in your org management account
* **Step 5:** Configure profiles using aws-vault, aws-sso-util 
* **Step 6:** Configure Pathfinding Labs' terraform.tfvars with the three AWS profiles to use for prod, dev, and ops
* **Step 7:** Deploy Pathfinding Labs
* **Step 8:** Run `create_pathfinder_profiles.sh` to create the remaining profiles. 
