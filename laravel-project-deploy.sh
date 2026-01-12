#!/bin/sh
# this is for a Laravel project deployment

# if having trouble saving from via VSCode, you may have to do the following:
##########################################################################################################
# I am assuming the sudo username is user and the web server run as user www-data

# Do NOT uncomment these commands
# sudo usermod -a -G www-data user

# Set ownership to user:www-data
# sudo chown -R osi:www-data /home/user/root-web-directory

# Make files group-writable
# sudo chmod -R g+w /home/osi/root-web-directory

# Set group sticky bit so new files inherit www-data group
# sudo chmod g+s /home/user/root-web-directory
# find /home/user/root-web-directory -type d -exec sudo chmod g+s {} \;

# Assuming deploy.sh is in /home/user/root-web-directory
# sudo chown user:www-data /home/user/root-web-directory/deploy.sh
# sudo chmod 664 /home/user/root-web-directory/deploy.sh

# Make it executable
# sudo chmod +x /home/user/root-web-directory/deploy.sh

# Test you can write to a file
# echo "test" >> /home/user/root-web-directory/deploy.sh

# If this works without sudo, you're all set!

# Do NOT uncomment the above commands 
########################################################################################################


# remove comment if need
#export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -i /home/user/.ssh/id_ed25519"

WEB_HOME="/home/user/root-web-directory"
GIT_PATH="git@github.com:gituser/some-project.git"
GIT_REPO_HOME="$WEB_HOME/releases"
BRANCH="production"
LOG_FILE="/$WEB_HOME/deployment.log"
CURRENT_LINK="$WEB_HOME/current"
ENVIRONMENT="production"
SHARED_DIR="$WEB_HOME/shared"
KEEP_RELEASES=4

TIMESTAMP=`date +%Y%m%d_%H%M%S`

RELEASE_NAME=$TIMESTAMP

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

handle_error() {
    log "ERROR: Deployment failed at: $1"
    log "Rolling back to previous release..."
    
    if [ -L "$WEB_HOME/current" ]; then
        PREVIOUS_RELEASE=$(ls -t "$GIT_REPO_HOME" | sed -n '2p')
        if [ -n "$PREVIOUS_RELEASE" ]; then
            ln -nfs "$GIT_REPO_HOME/$PREVIOUS_RELEASE" "$WEB_HOME/current"
            log "Rolled back to: $PREVIOUS_RELEASE"
        fi
    fi
    
    exit 1
}

trap 'handle_error $LINENO' ERR


log "==================== DEBUG INFO ===================="
log "Running as user: $(whoami)"
#log "Home directory: $HOME"
log "Current directory: $(pwd)"
#log "SSH key file: $(ls -la ~/.ssh/id_ed25519 2>&1 || echo 'SSH key not found')"
#log "Git SSH command: $GIT_SSH_COMMAND"
log "Testing GitHub connection..."
ssh -T git@github.com 2>&1 | head -5 | tee -a "$LOG_FILE"
log "==================== END DEBUG ===================="

log "==================== Starting Deployment ===================="


cd $WEB_HOME                               # change directory to git_repo
#rm -rf sitename.com                             # remove old git files without interaction, change to the name of the git repo name
# Create directory structure if it doesn't exist
mkdir -p "$GIT_REPO_HOME"
mkdir -p "$SHARED_DIR"
mkdir -p "$SHARED_DIR/storage"


cd "releases"

log "Cloning repository from $BRANCH branch..."
git clone --depth 1 --branch "$BRANCH" "$GIT_PATH" "$GIT_REPO_HOME/$TIMESTAMP"

#cd `$WEB_HOME/current`

#check if the .env file is installed
# Copy .env from shared (or create if first deployment)
if [ -f "$SHARED_DIR/.env" ]; then
    log "Linking shared .env file..."
    ln -nfs "$SHARED_DIR/.env" "$GIT_REPO_HOME/$TIMESTAMP/.env"
else
    log "WARNING: No .env file found in shared directory!"
    log "Please create $SHARED_DIR/.env before the application will work"
fi

log "Setting up shared directories..."
mkdir -p "$SHARED_DIR/storage/app/public"
mkdir -p "$SHARED_DIR/storage/framework/cache"
mkdir -p "$SHARED_DIR/storage/framework/sessions"
mkdir -p "$SHARED_DIR/storage/framework/views"
mkdir -p "$SHARED_DIR/storage/logs"

# Remove release storage directory and symlink to shared
log "Linking shared storage..."
rm -rf "$GIT_REPO_HOME/$TIMESTAMP/storage"
ln -nfs "$SHARED_DIR/storage" "$GIT_REPO_HOME/$TIMESTAMP/storage"


cd "$GIT_REPO_HOME/$TIMESTAMP"

#check if composer is installed
log "Checking if composer is installed..."

# run the composer setup : composer.lock file should be available
composer install --optimize-autoloader --no-dev --no-interaction --prefer-dist

# Generate optimizations
log "Generating optimizations..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run database migrations
#log "Running database migrations..."
#php artisan migrate --force

# Create storage link if it doesn't exist
if [ ! -L "$RELEASE_DIR/public/storage" ]; then
    log "Creating storage link..."
    php artisan storage:link
fi

log "Switching to new release..."
ln -nfs "$GIT_REPO_HOME/$TIMESTAMP" "$CURRENT_LINK"

# Reload PHP-FPM to clear opcache
log "Reloading PHP-FPM..."
sudo systemctl reload php-fpm

# Clean up old releases
log "Cleaning up old releases (keeping last $KEEP_RELEASES)..."
cd "$GIT_REPO_HOME"
ls -t | tail -n +$((KEEP_RELEASES + 1)) | xargs -r rm -rf


log "==================== Deployment Completed Successfully ===================="
log "Release: $RELEASE_NAME"
log "Path: $GIT_REPO_HOME/$TIMESTAMP"
log "Current symlink: $CURRENT_LINK -> $GIT_REPO_HOME/$TIMESTAMP"
