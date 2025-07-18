#!/bin/sh

echo "WARNING: not checking for existing SSH keys or existing .gitconfig configuration file\!"

echo "What’s your git name?"
read GIT_SETUP_NAME
git config --global user.name $GIT_SETUP_NAME

echo "What’s your git email?"
read GIT_SETUP_EMAIL
git config --global user.email $GIT_SETUP_EMAIL

echo "Now configuring SSH keys..."
ssh-keygen -t rsa -C $GIT_SETUP_EMAIL

echo "Let’s start the ssh-agent..."
eval "$(ssh-agent -s)"

echo "Adding SSH key..."
ssh-add ~/.ssh/id_rsa

echo "Here is the key: SSH key to clipboard..."
cat ~/.ssh/id_rsa.pub

echo "Enabling SSH-based commit signing..."
git config --global gpg.format ssh
git config --global user.signingkey "$HOME/.ssh/id_rsa.pub"
git config --global commit.gpgsign true

echo "Setting Git defaults..."
git config --global core.editor "nvim"
git config --global core.autocrlf "input"
git config --global push.default "simple"
git config --global init.defaultBranch "main"
git config --global commit.template "~/dotfiles/.gitmessage"

echo "Now add your SSH key to GitHub (https://github.com/settings/keys)"
echo "Also add your public signing key ($HOME/.ssh/.id_rsa.pub) as a 'Signing Key'"
