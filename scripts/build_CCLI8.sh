#!/bin/bash

################# custom settings #######################

# set your prefered path to your v8.x.x cardano-cli binary
repoPath="${HOME}/git/spo-poll"
binaryDestinationPath="${HOME}/.local/bin/CIP-0094"

repoURL="https://github.com/input-output-hk/cardano-node.git"

targetTag="8.0.0-untested"

################# initial checks ########################

#if [ -d ${repoPath} ]; then
#    echo ""
#    echo "Local repository check: OK"
#    echo "(assuming you git clone'd https://github.com/input-output-hk/cardano-node.git into it)"
#else
#    echo "please set the path to your local cardano-node repository first and restart this script"
#    exit
#fi

mkdir -p ${binaryDestinationPath}
cd ${repoPath}

echo "リポジトリ ${repoURL} をダウンロードします"
echo "${targetTag} タグを使用します"
read -p "[Enter] を押して続けます ..."
git clone ${repoURL} cardano-node-poll
cd cardano-node-poll
git fetch --all --tags
git checkout ${targetTag}

echo ""
echo "バックアップ cabal.project.local to cabal.project.local.bkp_${targetTag} ..."
read -p "[Enter] を押して続けます ..."
#mv cabal.project.local cabal.project.local.bkp_${targetTag}

echo ""
echo "${targetTag} をベースにCabalを準備します" 
read -p "[Enter] を押して続けます ..."
cabal update
cabal configure -O0 -w ghc-8.10.7
echo "package cardano-crypto-praos" >> cabal.project.local
echo " flags: -external-libsodium-vrf" >> cabal.project.local

echo ""
echo "cardano-cliをビルド・インストールします" 
read -p "[Enter] を押して続けます ..."
cabal install \
  --installdir ${HOME}/.local/bin/CIP-0094 \
  --install-method=copy \
  --constraint "cardano-crypto-praos -external-libsodium-vrf" \
  --minimize-conflict-set \
  cardano-cli:exe:cardano-cli 2>&1 | tee /tmp/build.log

#echo ""
#ccli8Found=false
#grep -E "^Linking+.*cardano-cli" /tmp/build.log | while read -r line ; do
#    act_bin_path=$(echo "$line" | awk '{print $2}')
#    act_bin=$(echo "$act_bin_path" | awk -F "/" '{print $NF}')
#    echo "move new built to .local/bin/cardano-cli-cip0094 (not overwriting existing cardano-cli)"
#    read -p "[Enter] を押して続けます ..."
#    cp -f "$act_bin_path" "${HOME}/.local/bin/${act_bin}-cip0094"
#	ccli8Found=true
#done
#[[ "$ccli8Found" = false ]] && echo "Warn: cabal seems not having built cardano-cli";

echo ""
echo "以前のcabal.project.localファイルを復元します ..."
read -p "[Enter] を押して続けます ..."
#mv cabal.project.local.bkp_${targetTag} cabal.project.local
cd -

echo ""
echo "${targetTag} コードベースの新しいcardano-cliがインストールされました"
echo "${HOME}/.local/bin/CIP-0094/cardano-cli --version"
${HOME}/.local/bin/CIP-0094/cardano-cli --version

echo ""
echo "投票に参加するための getPoll.sh をダウンロードします"
read -p "[Enter] を押して続けます ..."
cd ${repoPath}
curl -s -o getPoll.sh "https://raw.githubusercontent.com/btbf/CIP-0094-polls/main/scripts/getPoll.sh"
chmod 755 getPoll.sh
echo "getPoll.sh を実行しますか？"
read -p "[Enter] を押して続けます ..."

./getPoll.sh
