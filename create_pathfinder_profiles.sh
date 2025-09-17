#!/bin/bash

# Script to create AWS profiles for Pathfinder-labs project using pathfinder starting users
# This script should be run after terraform apply to get the access keys

set -e  # Exit on any error

echo "🔧 Creating Pathfinder-labs AWS profiles for all environments..."
echo "============================================================="

# Function to check if profile exists
profile_exists() {
    local profile_name=$1
    
    # Check if the profile exists in AWS credentials
    if aws configure list-profiles | grep "^${profile_name}$"; then
        return 0  # Profile exists
    else
        return 1  # Profile doesn't exist
    fi
}

# List existing profiles
echo "📋 Checking for existing profiles..."
existing_profiles=()
for env in "dev" "prod" "operations"; do
    # Check starting user profiles
    profile_name="pl-pathfinder-starting-user-${env}"
    if profile_exists "$profile_name"; then
        existing_profiles+=("$profile_name")
        echo "   ⚠️  $profile_name already exists"
    else
        echo "   ✅ $profile_name does not exist"
    fi
    
    # Check admin cleanup user profiles
    admin_profile_name="pl-admin-cleanup-${env}"
    if profile_exists "$admin_profile_name"; then
        existing_profiles+=("$admin_profile_name")
        echo "   ⚠️  $admin_profile_name already exists"
    else
        echo "   ✅ $admin_profile_name does not exist"
    fi
done

if [ ${#existing_profiles[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Found ${#existing_profiles[@]} existing profile(s)"
    read -p "Do you want to overwrite existing profiles? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "⏭️  Skipping existing profiles. Only creating new ones."
        OVERWRITE_EXISTING=false
    else
        echo "🔄 Will overwrite existing profiles when prompted."
        OVERWRITE_EXISTING=true
    fi
else
    OVERWRITE_EXISTING=true
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. Please install it first."
    exit 1
fi

# Function to create profile for an environment
create_profile() {
    local env=$1
    local profile_type=$2  # "starting" or "admin"
    
    if [ "$profile_type" = "starting" ]; then
        local profile_name="pl-pathfinder-starting-user-${env}"
        local user_name="pl-pathfinder-starting-user-${env}"
        local access_key_var="${env}_pathfinder_starting_user_access_key_id"
        local secret_key_var="${env}_pathfinder_starting_user_secret_access_key"
    elif [ "$profile_type" = "admin" ]; then
        local profile_name="pl-admin-cleanup-${env}"
        local user_name="pl-admin-user-for-cleanup-scripts"
        local access_key_var="${env}_admin_user_for_cleanup_access_key_id"
        local secret_key_var="${env}_admin_user_for_cleanup_secret_access_key"
    else
        echo "❌ Unknown profile type: $profile_type"
        return 1
    fi
    
    echo ""
    echo "🔄 Processing ${profile_type} profile for ${env} environment..."
    
    # Check if profile already exists
    if profile_exists "$profile_name"; then
        if [ "$OVERWRITE_EXISTING" = false ]; then
            echo "⏭️  Skipping existing profile $profile_name (overwrite disabled)"
            return 0
        fi
        echo "⚠️  Profile $profile_name already exists"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "⏭️  Skipping profile $profile_name"
            return 0
        fi
        echo "🔄 Overwriting existing profile $profile_name..."
    else
        echo "🆕 Creating new profile $profile_name..."
    fi
    
    # Get the access key and secret from terraform output
    local access_key
    local secret_key
    
    access_key=$(terraform output -raw "$access_key_var")
    secret_key=$(terraform output -raw "$secret_key_var")
    
    # Configure the AWS profile
    aws configure set aws_access_key_id "$access_key" --profile "$profile_name"
    aws configure set aws_secret_access_key "$secret_key" --profile "$profile_name"
    aws configure set region "us-west-2" --profile "$profile_name"
    aws configure set output "json" --profile "$profile_name"
    
    if profile_exists "$profile_name"; then
        echo "✅ Updated profile: $profile_name"
    else
        echo "✅ Created profile: $profile_name"
    fi
    
    # Test the profile
    echo "🧪 Testing profile: $profile_name"
    if aws sts get-caller-identity --profile "$profile_name" &> /dev/null; then
        echo "✅ Profile $profile_name is working correctly"
        
        echo "👤 User: $user_name"
        aws sts get-caller-identity --profile "$profile_name" --query 'Account' --output text | xargs -I {} echo "🏢 Account: {}"
    else
        echo "❌ Profile $profile_name is not working correctly"
        return 1
    fi
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    echo "❌ This script must be run from the Pathfinder-labs project root directory"
    exit 1
fi

# Check if terraform has been initialized
if [ ! -d ".terraform" ]; then
    echo "❌ Terraform has not been initialized. Please run 'terraform init' first."
    exit 1
fi

# Check if terraform has been applied
if [ ! -f "terraform.tfstate" ]; then
    echo "❌ Terraform has not been applied. Please run 'terraform apply' first."
    exit 1
fi

echo "📋 Creating profiles for all environments..."

# Create profiles for each environment
for env in "dev" "prod" "operations"; do
    create_profile "$env" "starting"
    create_profile "$env" "admin"
done

echo ""
echo "🎉 All Pathfinder-labs profiles created successfully!"
echo "=================================================="
echo ""
echo "📋 Available profiles:"
echo ""
echo "🔓 Starting User Profiles (minimal permissions for privilege escalation demos):"
echo "   - pl-pathfinder-starting-user-dev        (Development environment)"
echo "   - pl-pathfinder-starting-user-prod       (Production environment)"
echo "   - pl-pathfinder-starting-user-operations (Operations environment)"
echo ""
echo "🔑 Admin Cleanup Profiles (full permissions for cleanup scripts):"
echo "   - pl-admin-cleanup-dev                   (Development environment)"
echo "   - pl-admin-cleanup-prod                  (Production environment)"
echo "   - pl-admin-cleanup-operations            (Operations environment)"
echo ""
echo "💡 Usage examples:"
echo "   # Demo scripts (use starting user profiles):"
echo "   aws sts get-caller-identity --profile pl-pathfinder-starting-user-prod"
echo ""
echo "   # Cleanup scripts (use admin cleanup profiles):"
echo "   aws sts get-caller-identity --profile pl-admin-cleanup-prod"
echo ""
echo "🔒 Starting user profiles have minimal permissions for privilege escalation demos"
echo "🔑 Admin cleanup profiles have full AdministratorAccess for cleanup operations"
