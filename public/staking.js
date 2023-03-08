let contract = null;
const supportedNetworks = {
    Polygon: {
        Name: 'Polygon Mainnet',
        ChainId: 137
    },
    Mumbai: {
        Name: 'Mumbai',
        ChainId: 80001
    },
    Eth: {
        Name: 'Ethereum Mainnet',
        ChainId: 1
    },
    Rinkeby: {
        Name: 'Rinkeby',
        ChainId: 4
    },
}

const currentNetwork = supportedNetworks.Rinkeby;

const config = {
    contractAddress: '0xBD1150f87EBA437f4917c64548F8fBd742CCE3ec',
    networkName: currentNetwork.Name,
    etherScanUrl: 'https://rinkeby.etherscan.io/tx/',
    openSeaUrl: 'https://opensea.io/account',
    networkParams: {
        chainId: window.ethers.utils.hexValue(currentNetwork.ChainId)
    },
    contractABI: [
        "function nftToken() public view returns(address)",
        "function getStaked(address targetAddress) external view returns (string[] memory, uint256[] memory)",
        "function stakeNFT(uint256[] calldata tokenId) public returns (bool)",
        "function tokenURIs(address targetAddress) public view returns(string[] memory, uint256[] memory)",
        "function unStakeNFT(uint256[] calldata tokenId) public nonReentrant returns (bool)",
        "function claimRewards(uint256 tokenId) external",
        "function userCanClaim() public view returns(bool)",
        "function getCurrentStakeEarned(uint256 tokenId) public view returns (uint256)",
        "function getCurrentTotalStakeEarned(address targetAddress) external view returns (uint256)",
    ]
};


let targetContract = null;
let collectionContractAddress = null;

let targetAbi = [
    "function isApprovedForAll(address owner, address operator) public view returns (bool)",
    "function setApprovalForAll(address operator, bool approved) public",
];

// fill up info

async function sendTransaction(data, transactionFuncName, contractABI, contractAddress) {
    const modal = document.querySelector('.nft-modal');
    modal.classList.add('open');

    const modalContainer = modal.querySelector('.nft-modal-container');

    modalContainer.innerHTML = `
      <div class="nft-modal-content">
        <img src="images/loader.gif" class="loader img-fluid">
      </div>
    `;

    function displayError(error) {
        modalContainer.innerHTML = `
        <div class="nft-modal-content">
          ${error}
        </div>
      `;
        return false;
    };

    if (!(await verifyWalletConnection())) {
        return displayError('Error with MetaMask. Please refresh and try again.');
    }
    const modalContent = modal.querySelector('.nft-modal-content');

    const iface = new ethers.utils.Interface(contractABI);
    const params = iface.encodeFunctionData(transactionFuncName, data);
    try {
        const txHash = await window.ethereum.request({
            method: 'eth_sendTransaction',
            params: [{
                from: window.ethereum.selectedAddress,
                to: contractAddress,
                value: "0x0",
                data: params
            }, ],
        });
        modalContent.innerHTML = `<p>Transaction submitted. Please wait for confirmation.</p>

        <p>Transaction hash: ${txHash} </p>

        <a target="_blank" href="${config.etherScanUrl}${txHash}">View on EtherScan</a>
        <br>
        <img src="images/loader.gif" class="loader img-fluid">`;
        const tx = await (new ethers.providers.Web3Provider(window.ethereum)).getTransaction(txHash);
        const txReceipt = await tx.wait();
        modal.classList.remove('open');
        return true;
    } catch (err) {
        console.log(err);
        return displayError("Error with Transaction. Please refresh and try again!");
    }
}

async function verifyWalletConnection({
    noAlert
} = {}) {
    if (!window.ethereum) {
        displayError('Please install MetaMask to interact with this feature');
        return;
    }

    if (!window.ethereum.selectedAddress && noAlert && localStorage.getItem('verifyWalletRequested') === '1') {
        return;
    }

    // localStorage.setItem('verifyWalletRequested', '1');
    let accounts;
    try {
        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{
                chainId: config.networkParams.chainId
            }], // chainId must be in hexadecimal numbers
        });
        accounts = await window.ethereum.request({
            method: 'eth_requestAccounts'
        });

        if (window.ethereum.chainId != config.networkParams.chainId) {
            alert(`Please switch MetaMask network to ${config.networkName}`);
            return;
        }
    } catch (error) {
        if (error.code == -32002) {
            alert('Please open your MetaMask and select an account');
            return;
        } else if (error.code == 4001) {
            alert('Please connect with MetaMask');
            return;
        } else if (error.code == 4902) {
            alert('Unrecognized network, please check metmask and try again');
            return;
        } else {
            throw error;
        }
    }
    console.log("main contract address", `[${config.contractAddress}]`);
    contract = new ethers.Contract(config.contractAddress, config.contractABI, new ethers.providers.Web3Provider(window.ethereum));
    collectionContractAddress = await contract.nftToken();
    console.log("target contract adress", `[${collectionContractAddress}]`);
    targetContract = new ethers.Contract(collectionContractAddress, targetAbi, new ethers.providers.Web3Provider(window.ethereum));
    return accounts[0];
}

async function isApprovedForAll() {
    let approveBtn = document.getElementById("approveBtn");
    let approved = await targetContract.isApprovedForAll(window.ethereum.selectedAddress, config.contractAddress)
    if (!approved) {
        approveBtn.setAttribute("disabled", true);
        let data = [config.contractAddress, true];
        approved = await sendTransaction(data, "setApprovalForAll", targetAbi, collectionContractAddress);
        approveBtn.removeAttribute("disabled");
    }
    return approved;
}


async function init() {
    let showStakable = document.getElementById("showStakable")
    let showStaked = document.getElementById("showStaked");

    function createTokenImage(tokenURI, dataId, root, i, imgClass) {
        tokenURI = tokenURI.replace("ipfs://", "https://ipfs.io/ipfs/")
        let parrentDiv = document.createElement("div");
        let img = new Image();
        parrentDiv.classList.add("bktibx");
        parrentDiv.classList.add(imgClass);
        parrentDiv.style.order = i;
        parrentDiv.setAttribute("dataId", dataId);
        parrentDiv.appendChild(img);
        root.appendChild(parrentDiv)
        parrentDiv.addEventListener("click", function () {
            if (parrentDiv.classList.contains("unstaked")) {
                parrentDiv.classList.remove("unstaked");
                parrentDiv.classList.add("staked");
            } else if (parrentDiv.classList.contains("staked")) {
                parrentDiv.classList.add("unstaked");
                parrentDiv.classList.remove("staked");
            }
        });
        fetch(tokenURI)
            .then(res => res.json())
            .then(out => {
                img.src = out.image.replace("ipfs://", "https://ipfs.io/ipfs/")
            });
    }

    // CREATE TOKEN IMAGES
    console.log("user address", `[${window.ethereum.selectedAddress}]`);
    let getTokenUris = (await contract.tokenURIs(window.ethereum.selectedAddress));
    getTokenUris[0].forEach((tokenURI, i) => {
        createTokenImage(tokenURI, getTokenUris[1][i], showStakable, i, "unstaked")
    });

    let getTotalreward = document.getElementById("claimAmmount");
    let getTotalEarn = (await contract.getCurrentTotalStakeEarned(window.ethereum.selectedAddress));
    getTotalreward.innerHTML = `Total Token Rewards = ` + ethers.utils.formatUnits(getTotalEarn);

    console.log("GOT AVAILABLE TOKENS");
    let getStaked = (await contract.getStaked(window.ethereum.selectedAddress));
    getStaked[0].forEach((tokenURI, i) => {
        createTokenImage(tokenURI, getStaked[1][i], showStaked, i, "staked");
    });
    console.log("GOT STAKED");


    async function stakeTransaction(fromElement, toElement, className, transactionFuncName) {
        let tokens = [];
        let tokenChildren = fromElement.getElementsByClassName(className)
        Array.from(tokenChildren).forEach((el) => {
            tokens.push(+el.getAttribute("dataId"));
        });
        console.log(tokens);
        if (await sendTransaction([tokens], transactionFuncName, config.contractABI, config.contractAddress)) {
            Array.from(tokenChildren).forEach((el) => {
                toElement.appendChild(el);
            });
        }
    }

    let stakeBtn = document.getElementById("stakeBtn");
    stakeBtn.addEventListener("click", async function () {
        await stakeTransaction(showStakable, showStaked, "staked", "stakeNFT");
        //scroll not working here
        $("#stakeBtn").attr("disabled", true);
    });
    let unstakeBtn = document.getElementById("unstakeBtn");
    unstakeBtn.addEventListener("click", async function () {
        await stakeTransaction(showStaked, showStakable, "unstaked", "unStakeNFT");
        $("#unstakeBtn").attr("disabled", true);

    });


    let claimBtn = document.getElementById("claimBtn");
    claimBtn.addEventListener("click", async function () {
        await stakeTransaction(showStaked, showStakable, "unstaked", "claimRewards");
        $("#claimBtn").attr("disabled", true);

    });

    console.log("CLAIM CHECKED");
    console.log("UPDATED claim ammount");

    document.getElementById("content").classList.remove("hidden");
    Array.from(document.getElementsByClassName("tslshow")).forEach((view) => {
        console.log(view)
        $(view).slick({
            dots: false,
            infinite: false,
            speed: 300,
            slidesToShow: 4,
            slidesToScroll: 1,
            arrows: true,
            prevArrow: "<button type='button' class='slick-prev pull-left'><i class='fa fa-angle-left' aria-hidden='true'></i></button>",
            nextArrow: "<button type='button' class='slick-next pull-right'><i class='fa fa-angle-right' aria-hidden='true'></i></button>",
        });
    });
}

$(document).ready(function () {
    let modal = document.createElement("div");
    modal.innerHTML = `<div class="nft-modal">
        <div class="nft-modal-overlay nft-js-modal-overlay"></div>
        <div class="nft-modal-container"></div>
    </div>`
    document.body.appendChild(modal);

    document.getElementById("checkWalletConnection").addEventListener("click", async () => {
        if (await verifyWalletConnection()) {
            document.getElementById("checkWalletConnection").remove();
            let approveBtn = document.getElementById("approveBtn");
            if (await targetContract.isApprovedForAll(window.ethereum.selectedAddress, config.contractAddress)) {
                approveBtn.remove();
                console.log("approved");
                await init();
            } else {
                approveBtn.classList.remove("hidden");
                approveBtn.addEventListener("click", async () => {
                    if (await isApprovedForAll()) {
                        approveBtn.remove();
                        await init();
                    }
                });
            }

        }

        let selectShowStaked = $('#showStaked .bktibx');
        let selectshowStakable = $('#showStakable .bktibx');
        if (selectShowStaked.children().length == 1) {
            selectShowStaked.css("min-width", "184px");
            $("#showStaked .slick-list .slick-track").css("min-width", "228px");
        } else if (selectShowStaked.children().length == 2) {
            selectShowStaked.css("min-width", "184px");
            $("#showStaked .slick-list .slick-track").css("min-width", "486px");
        } else if (selectShowStaked.children().length == 3) {
            selectShowStaked.css("min-width", "184px");
            $("#showStaked .slick-list .slick-track").css("min-width", "683px");
        }

        if (selectshowStakable.children().length == 1) {
            selectshowStakable.css("min-width", "184px");
            $("#showStakable .slick-list .slick-track").css("min-width", "228px");
        } else if (selectshowStakable.children().length == 2) {
            selectshowStakable.css("min-width", "184px");
            $("#showStakable .slick-list .slick-track").css("min-width", "486px");
        } else if (selectshowStakable.children().length == 3) {
            selectshowStakable.css("min-width", "184px");
            $("#showStakable .slick-list .slick-track").css("min-width", "683px");
        }



        let userCanClaim = await contract.userCanClaim();
        if (userCanClaim == false) {
            $("#claimBtn").attr("disabled", true);
            console.log("CanClaim", userCanClaim);
        } else {
            console.log("CanClaim", userCanClaim);
            $('body').on('click', '#showStaked .bktibx', function () {

                if ($(this).hasClass('staked')) {
                    $("#claimBtn").attr("disabled", true);
                } else {
                    $("#claimBtn").attr("disabled", false);
                }
            });
        }
    });
});