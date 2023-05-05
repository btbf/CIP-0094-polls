#!/bin/bash

################# custom settings #######################

# set your prefered path to your v8.x.x cardano-cli binary
#CCLI8="${HOME}/.local/bin/cardano-cli"
peyment_file=payment.addr
################# initial checks ########################

# assume the v8 exe built and installed by the build_CCLI8 script
if [ -z ${CCLI8} ]; then
    if [ -f "${HOME}/.local/bin/CIP-0094/cardano-cli" ]; then
        CCLI8="${HOME}/.local/bin/CIP-0094/cardano-cli"
    else
	    # if not found, let's look for the default cardano-cli exe
        CCLI8=$(whereis cardano-cli | cut -d' ' -f2)
		if [ -z ${CCLI8} ]; then 
		    echo "Warn: no cardano-cli exe found. exiting"
			exit
		fi
	fi
fi

# we need at least v8.x.x
cli_version=$(${CCLI8} --version 2>/dev/null | head -n 1 | cut -d' ' -f2)
if [[ $(echo $cli_version | cut -d'.' -f1) -lt 8 ]]; then
    echo "Warn: cardano-cli version $cli_version does not support governance poll commands"
    exit
else
    echo "Using ${CCLI8} version ${cli_version} ..."
fi

####################  and Go  ###########################
echo  "   _____ ____  ____                    ____
  / ___// __ \/ __ \      ____  ____  / / /
  \__ \/ /_/ / / / /_____/ __ \/ __ \/ / / 
 ___/ / ____/ /_/ /_____/ /_/ / /_/ / / /  
/____/_/    \____/     / .___/\____/_/_/   
                      /_/                  
"

PS3='Which network should we look at? '
options=("PreProd" "Mainnet" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "PreProd")
            echo "OK so be it $opt"
            network='preprod'
            options=("PreProd Demo Poll (epoch 86 - 1 May 2023)" "Other" "Quit")
            break
            ;;
        "Mainnet")
            echo "OK so be it $opt"
            network='mainnet'
            options=("Mainnet SPO-Poll (epoch ... - .. May 2023)" "Other" "Quit")
            break
            ;;
        "Quit")
            echo "Good bye!"
            exit
            ;;
        *) echo "invalid option $REPLY";;
    esac
done

echo ""
PS3='Which poll TX should we look at? '
select opt in "${options[@]}"
do
    case $opt in
        "PreProd Demo Poll (epoch 86 - 1 May 2023)")
            txHash='d8c1b1d871a27d74fbddfa16d28ce38288411a75c5d3561bb74066bcd54689e2'
            echo "OK so TX ${txHash}"
            break
            ;;
        "Mainnet SPO-Poll (epoch ... - .. May 2023)")
            txHash='b3-a-b1t-pat13nt-plz...'
            echo "OK so TX ${txHash}"
            break
            ;;
        "Other")
            echo "Please specify the tx hash"
            read txHash
            echo "OK so TX ${txHash}"
            break
            ;;
        "Quit")
            echo "Good bye!"
            exit
            ;;
        *) echo "invalid option $REPLY";;
    esac
done


echo "Query ${network}: ${txHash} metadata ..."


tx=$(curl -sX POST "https://${network}.koios.rest/api/v0/tx_metadata"  -H "accept: application/json" -H "content-type: application/json"  -d "{\"_tx_hashes\":[\"${txHash}\"]}") 
txMeta=$(echo $tx | jq -r .[0].metadata)


if [[ -n $(echo $txMeta | jq -r '.["94"]') ]]; then
    echo "Looks promising: TX metadata has a CIP-0094 label"
    #query the TX in CBOR format from cardano-foundation/CIP-0049-polls (interim solution for preprod)
    txCBOR=$(curl -s GET "https://raw.githubusercontent.com/gufmar/CIP-0049-polls/main/networks/preprod/${txHash}/poll-CBOR.json")
    echo "$txCBOR" > ${HOME}/git/spo-poll/CIP-0094_${txHash}-CBOR.json
	echo ""
    answer_file="CIP-0094_${txHash}-poll-answer.json"
    ${CCLI8} governance answer-poll --poll-file ${HOME}/git/spo-poll/CIP-0094_${txHash}-CBOR.json 1> ${HOME}/git/spo-poll/${answer_file}
	echo ""
    echo "Metadata for your answer TX is ready in ${HOME}/git/spo-poll/${answer_file}"
else
    echo "Warn: TX has no CIP-0094 metadata label. Exiting"
fi

echo
echo "Txファイルを作成します"
read -p "[Enter] を押して続けます ..."

echo
cd $NODE_HOME
currentSlot=$(cardano-cli query tip $NODE_NETWORK | jq -r '.slot')
echo 現在のスロット: $currentSlot 

if [-e $peyment_file]; then
    cardano-cli query utxo \
        --address $(cat ${peyment_file}) \
        $NODE_NETWORK > fullUtxo.out

    tail -n +3 fullUtxo.out | sort -k3 -nr | sed -e '/lovelace + [0-9]/d' > balance.out

    cat balance.out

    tx_in=""
    total_balance=0
    while read -r utxo; do
        in_addr=$(awk '{ print $1 }' <<< "${utxo}")
        idx=$(awk '{ print $2 }' <<< "${utxo}")
        utxo_balance=$(awk '{ print $3 }' <<< "${utxo}")
        total_balance=$((${total_balance}+${utxo_balance}))
        echo TxHash: ${in_addr}#${idx}
        echo ADA: ${utxo_balance}
        tx_in="${tx_in} --tx-in ${in_addr}#${idx}"
    done < balance.out
    txcnt=$(cat balance.out | wc -l)
    echo Total ADA balance: ${total_balance}
    echo Number of UTXOs: ${txcnt}

    cardano-cli transaction build-raw \
        ${tx_in} \
        --tx-out $(cat ${peyment_file})+${total_balance} \
        --invalid-hereafter $(( ${currentSlot} + 10000)) \
        --fee 0 \
        --metadata-json-file ~/git/spo-poll/${answer_file} \
        --out-file tx.tmp

    fee=$(cardano-cli transaction calculate-min-fee \
        --tx-body-file tx.tmp \
        --tx-in-count ${txcnt} \
        --tx-out-count 1 \
        $NODE_NETWORK \
        --witness-count 2 \
        --byron-witness-count 0 \
        --protocol-params-file params.json | awk '{ print $1 }')
    echo fee: $fee

    txOut=$((${total_balance}-${fee}))
    echo txOut: ${txOut}

    cardano-cli transaction build-raw \
        ${tx_in} \
        --tx-out $(cat ${peyment_file})+${txOut} \
        --invalid-hereafter $(( ${currentSlot} + 10000)) \
        --fee ${fee} \
        --json-metadata-detailed-schema \
        --metadata-json-file ~/git/spo-poll/${answer_file} \
        --out-file tx.raw

    echo
    echo "tx.rawを作成しました"
    echo "エアギャップにコピーして署名してください"
    echo
fi
