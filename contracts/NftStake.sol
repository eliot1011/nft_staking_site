// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract NftStake is IERC721Receiver, ReentrancyGuard {
    using SafeMath for uint256;

    IERC721 public nftToken;
    IERC20 public erc20Token;


    address public constant collectionAddress = 0x31A28edaf8b71483e0944a7597E5FEfF710A6152;
    address public daoAdmin;
    uint256 public tokensPerBlock;
    bool    public canClaim = false;

    struct stake {
        uint256 tokenId;
        uint256 stakedFromBlock;
        address owner;
    }

    // TokenID => Stake
    mapping(uint256 => stake) public receipt;


    uint256 public numberOfStaked;

    uint256[] public _allTokens;
    mapping(uint256 => uint256) public _allTokensIndex;

    mapping(address => mapping(uint256 => uint256)) public _ownedTokens;
    mapping(uint256 => uint256) public _ownedTokensIndex;
    mapping(address => uint256) public _balances;

    event NftStaked(address indexed staker, uint256 tokenId, uint256 blockNumber);
    event NftUnStaked(address indexed staker, uint256 tokenId, uint256 blockNumber);
    event StakePayout(address indexed staker, uint256 tokenId, uint256 stakeAmount, uint256 fromBlock, uint256 toBlock);
    event StakeRewardUpdated(uint256 rewardPerBlock);

    modifier onlyStaker(uint256 tokenId) {
        // require that this contract has the NFT
        require(nftToken.ownerOf(tokenId) == address(this), "onlyStaker: Contract is not owner of this NFT");

        // require that this token is staked
        require(receipt[tokenId].stakedFromBlock != 0, "onlyStaker: Token is not staked");

        // require that msg.sender is the owner of this nft
        require(receipt[tokenId].owner == msg.sender, "onlyStaker: Caller is not NFT stake owner");

        _;
    }

    modifier requireTimeElapsed(uint256 tokenId) {
        // require that some time has elapsed (IE you can not stake and unstake in the same block)
        require(
            receipt[tokenId].stakedFromBlock < block.number,
            "requireTimeElapsed: Can not stake/unStake/claim in same block"
        );
        _;
    }

    modifier onlyDao() {
        require(msg.sender == daoAdmin, "reclaimTokens: Caller is not the DAO");
        _;
    }

    constructor(
        IERC721 _nftToken,
        IERC20 _erc20Token,
        address _daoAdmin,
        uint256 _tokensPerBlock
    ) {
        nftToken = _nftToken;
        erc20Token = _erc20Token;
        daoAdmin = _daoAdmin;
        tokensPerBlock = _tokensPerBlock;

        emit StakeRewardUpdated(tokensPerBlock);
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    //User must give this contract permission to take ownership of it.
    function stakeNFT(uint256[] calldata tokenId) public nonReentrant returns (bool) {
        // allow for staking multiple NFTS at one time.
        for (uint256 i = 0; i < tokenId.length; i++) {
            _stakeNFT(tokenId[i]);
            _addTokenToOwnerEnumeration(msg.sender, tokenId[i]);
        }

        return true;
    }

    function getStakeContractBalance() public view returns (uint256) {
        return erc20Token.balanceOf(address(this));
    }

    //Call Total Stake earn for TargetAddress
    function getCurrentTotalStakeEarned(address targetAddress) external view returns (uint256) {
        uint256 [] memory tokenIds = new uint256[](_balances[targetAddress]); 
        uint256 [] memory tokenRewards = new uint256[](_balances[targetAddress]); 
        uint256 result;
        for(uint256 i = 0; i < _balances[targetAddress]; i++){
            tokenIds[i] = _ownedTokens[targetAddress][i];
            tokenRewards[i] = _getTimeStaked(tokenIds[i]).mul(tokensPerBlock);
            result += tokenRewards[i];
        }
        return (result);
    }

    //Call Stake earn of every token owned for TargetAddress
    function getCurrentStakeEarned(uint256 tokenId) public view returns (uint256) {
        return _getTimeStaked(tokenId).mul(tokensPerBlock);
    }

    function unStakeNFT(uint256[] calldata tokenId) public nonReentrant returns (bool) {
        for(uint256 i = 0; i < tokenId.length; i++){
            _unStakeNFT(tokenId[i]);
            _removeTokenFromOwnerEnumeration(msg.sender, tokenId[i]);
        }
        return true;
    }

    function _unStakeNFT(uint256 tokenId) internal onlyStaker(tokenId) requireTimeElapsed(tokenId) returns (bool) {
        // payout stake, this should be safe as the function is non-reentrant
        _payoutStake(tokenId);

        // delete stake record, effectively unstaking it
        delete receipt[tokenId];

        // return token
        nftToken.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NftUnStaked(msg.sender, tokenId, block.number);

        return true;
    }

    function tokenURIs(address targetAddress) public view returns(string[] memory, uint256[] memory){
        ERC721Enumerable collectionContract = ERC721Enumerable(collectionAddress);
        uint256 targetBalance = collectionContract.balanceOf(targetAddress);
        string [] memory uris = new string[](targetBalance); 
        uint256 [] memory tokenIds = new uint256[](targetBalance); 
        for(uint256 i = 0; i < targetBalance; i++){
            uint256 tokenId = collectionContract.tokenOfOwnerByIndex(targetAddress, i);
            uris[i] = collectionContract.tokenURI(tokenId);
            tokenIds[i] = tokenId;
        }
        return (uris, tokenIds);
    }

        function getStaked(address targetAddress) external view returns (string[] memory, uint256[] memory) {
        string [] memory uris = new string[](_balances[targetAddress]); 
        uint256 [] memory tokenIds = new uint256[](_balances[targetAddress]); 
        for(uint256 i = 0; i < _balances[targetAddress]; i++){
            tokenIds[i] = _ownedTokens[targetAddress][i];
            uris[i] =  ERC721Enumerable(collectionAddress).tokenURI(tokenIds[i]);
        }
        return (uris, tokenIds);
    }
    
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = _balances[to];
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
        _balances[to]++;
        _addTokenToAllTokensEnumeration(tokenId);
        numberOfStaked++;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _balances[from] - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
        _balances[from]--;
        _removeTokenFromAllTokensEnumeration(tokenId);
        numberOfStaked--;
    }

    //Allows you to claim rewards, but canClaim must be true
    function claimRewards(uint256 tokenId) external {
        require(canClaim == true, "You cannot claim yet!");
        // This 'payout first' should be safe as the function is nonReentrant
        _payoutStake(tokenId);

        // update receipt with a new block number
        receipt[tokenId].stakedFromBlock = block.number;
        
    }

    function changeTokensPerblock(uint256 _tokensPerBlock) public onlyDao {
        tokensPerBlock = _tokensPerBlock;

        emit StakeRewardUpdated(tokensPerBlock);
    }

    function reclaimTokens() external onlyDao {
        erc20Token.transfer(daoAdmin, erc20Token.balanceOf(address(this)));
    }

    function setCanClaim(bool _state) public onlyDao {
    canClaim = _state;
    }

      function userCanClaim() public view returns(bool) {
    return canClaim;
    }

    function _stakeNFT(uint256 tokenId) internal returns (bool) {
        // require this token is not already staked
        require(receipt[tokenId].stakedFromBlock == 0, "Stake: Token is already staked");

        // require this token is not already owned by this contract
        require(nftToken.ownerOf(tokenId) != address(this), "Stake: Token is already staked in this contract");

        // take possession of the NFT
        nftToken.safeTransferFrom(msg.sender, address(this), tokenId);

        // check that this contract is the owner
        require(nftToken.ownerOf(tokenId) == address(this), "Stake: Failed to take possession of NFT");

        // start the staking from this block.
        receipt[tokenId].tokenId = tokenId;
        receipt[tokenId].stakedFromBlock = block.number;
        receipt[tokenId].owner = msg.sender;

        emit NftStaked(msg.sender, tokenId, block.number);

        return true;
    }

    function _payoutStake(uint256 tokenId) internal {
        /* NOTE : Must be called from non-reentrant function to be safe!*/

        // double check that the receipt exists and we're not staking from block 0
        require(receipt[tokenId].stakedFromBlock > 0, "_payoutStake: Can not stake from block 0");

        // earned amount is difference between the stake start block, current block multiplied by stake amount
        uint256 timeStaked = _getTimeStaked(tokenId).sub(1); // don't pay for the tx block of withdrawl
        uint256 payout = timeStaked.mul(tokensPerBlock);

        // If contract does not have enough tokens to pay out, return the NFT without payment
        // This prevent a NFT being locked in the contract when empty
        if (erc20Token.balanceOf(address(this)) < payout) {
            emit StakePayout(msg.sender, tokenId, 0, receipt[tokenId].stakedFromBlock, block.number);
            return;
        }

        // payout stake
        erc20Token.transfer(receipt[tokenId].owner, payout);

        emit StakePayout(msg.sender, tokenId, payout, receipt[tokenId].stakedFromBlock, block.number);
    }

    function _getTimeStaked(uint256 tokenId) internal view returns (uint256) {
        if (receipt[tokenId].stakedFromBlock == 0) {
            return 0;
        }

        return block.number.sub(receipt[tokenId].stakedFromBlock);
    }

    /** Add Function to allow the DAO to forcibly unstake an NFT and return it to the owner */
}