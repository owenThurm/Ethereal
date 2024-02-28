pragma solidity ^0.8.0;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/utils/Pausable.sol";
import "openzeppelin-contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";

interface IwstETH {
    function balanceOf(address account) external returns (uint256);
    function getStETHByWstETH(uint256 amount) external view returns (uint256);
    function getWstETHByStETH(uint256 amount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
    function transfer(address recipient, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);
}

contract Ethereal is Ownable, Pausable, ERC721URIStorage, ERC721Holder, ReentrancyGuard {

    /* ======== EVENTS ======== */
    event CreateCollection(uint256 indexed id);
    event CreateGem(uint256 indexed id);
    event CeaseGem(uint256 indexed id);
    event GemMinted(uint256 indexed id, address indexed minter, uint256 value);
    event GemRedeemed(uint256 indexed id, address indexed redeemer, uint256 value);

    /* ======== STATE VARIABLES ======== */
    struct Collection {
        string name;
        bool validator;
        address validatorAddress;
        bool ethereum;
        string baseURI;
    }

    struct Gem {
        uint256 collection;
        uint256 denomination;
        uint256 redeemFee; // % reward (3 decimals: 100 = 1%)
        bool active;
    }

    struct Metadata {
        uint256 balance;
        uint256 collection;
        uint256 gem;
    }

    Collection[] public collections;
    Gem[] public gems;

    mapping(uint256 => Metadata) public metadata;

    uint256 internal circulatingGems = 0;
    uint256 public fees = 0;

    address public wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public payout;
    uint256 private _tokenCounter;

    /* ======== CONSTRUCTOR ======== */
    constructor() ERC721("Ethereal", "ETHRL") Ownable(msg.sender) {
        payout = msg.sender;
    }

    /* ======== FUNCTIONS ======== */
    function createCollection(
        string memory _name,
        bool _validator,
        address _validatorAddress,
        bool _ethereum,
        string memory _baseURI
    ) external onlyOwner returns (uint256 id_) {
        id_ = collections.length;

        collections.push(
            Collection({
                name: _name,
                validator: _validator,
                validatorAddress: _validatorAddress,
                ethereum: _ethereum,
                baseURI: _baseURI
            })
        );

        emit CreateCollection(id_);
    }

    function createGem(uint256 _collection, uint256 _denomination, uint256 _redeemFee, bool _active)
        external
        onlyOwner
        returns (uint256 id_)
    {
        id_ = gems.length;

        gems.push(Gem({collection: _collection, denomination: _denomination, redeemFee: _redeemFee, active: _active}));

        emit CreateGem(id_);
    }

    function updateCollection(
        uint256 _id,
        string memory _name,
        bool _validator,
        address _validatorAddress,
        bool _ethereum,
        string memory _baseURI
    ) external onlyOwner {
        collections[_id].name = _name;
        collections[_id].validator = _validator;
        collections[_id].validatorAddress = _validatorAddress;
        collections[_id].ethereum = _ethereum;
        collections[_id].baseURI = _baseURI;
    }

    function updateGem(uint256 _id, uint256 _collection, uint256 _denomination, uint256 _redeemFee, bool _active)
        external
        onlyOwner
    {
        gems[_id].collection = _collection;
        gems[_id].denomination = _denomination;
        gems[_id].redeemFee = _redeemFee;
        gems[_id].active = _active;
    }

    function ceaseGem(uint256 _id) external onlyOwner {
        gems[_id].active = false;
        emit CeaseGem(_id);
    }

    function _mintEth(uint256 _id, uint256 _collection, address _recipient) internal returns (uint256 tokenId_) {
        tokenId_ = ++_tokenCounter;
        _safeMint(_recipient, tokenId_);
        circulatingGems++;
        metadata[tokenId_] = Metadata(msg.value, _collection, _id);
        emit GemMinted(tokenId_, _recipient, msg.value);
    }

    function _mintWstEth(uint256 _id, uint256 _collection, address _recipient) internal returns (uint256 tokenId_) {
        tokenId_ = ++_tokenCounter;
        _safeMint(_recipient, tokenId_);
        circulatingGems++;
        uint256 preBalance = IwstETH(wstETH).balanceOf(address(this));
        (bool success,) = wstETH.call{value: msg.value}("");
        require(success, "Failed to deposit Ether");
        metadata[tokenId_] = Metadata(IwstETH(wstETH).balanceOf(address(this)) - preBalance, _collection, _id);
        emit GemMinted(tokenId_, _recipient, msg.value);
    }

    function mint(uint256 _id, address _recipient)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 tokenId_)
    {
        require(msg.value == gems[_id].denomination, "Wrong ether amount");
        if (collections[gems[_id].collection].validator) {
            require(collections[gems[_id].collection].validatorAddress == msg.sender, "Not Validator");
        }
        require(gems[_id].active, "No longer mintable");
        if (collections[gems[_id].collection].ethereum) {
            return _mintEth(_id, gems[_id].collection, _recipient);
        } else {
            return _mintWstEth(_id, gems[_id].collection, _recipient);
        }
    }

    function _redeemEth(uint256 _tokenId) internal {
        safeTransferFrom(msg.sender, address(this), _tokenId);
        _burn(_tokenId);
        circulatingGems--;
        uint256 redeemFee = (metadata[_tokenId].balance * gems[metadata[_tokenId].gem].redeemFee) / 1e4;
        uint256 amount = metadata[_tokenId].balance - redeemFee;
        fees += redeemFee;
        metadata[_tokenId].balance = 0;
        (bool success,) = msg.sender.call{value: amount}(" ");
        require(success, " ");
        emit GemRedeemed(_tokenId, msg.sender, amount);
    }

    function _redeemWstEth(uint256 _tokenId) internal {
        safeTransferFrom(msg.sender, address(this), _tokenId);
        uint256 redeemFee = metadata[_tokenId].balance * gems[metadata[_tokenId].gem].redeemFee / 1e4;
        uint256 amount = metadata[_tokenId].balance - redeemFee;
        fees += redeemFee;
        metadata[_tokenId].balance = 0;
        _burn(_tokenId);
        circulatingGems--;
        IwstETH(wstETH).transfer(msg.sender, amount);
        emit GemRedeemed(_tokenId, msg.sender, amount);
    }

    function redeem(uint256 _tokenId) external nonReentrant {
        address owner = ownerOf(_tokenId);
        _checkAuthorized(owner, msg.sender, _tokenId);
        if (collections[metadata[_tokenId].collection].ethereum) {
            _redeemEth(_tokenId);
        } else {
            _redeemWstEth(_tokenId);
        }
    }

    function getTokenCollectionName(uint256 _tokenId) public view returns (string memory) {
        return collections[metadata[_tokenId].collection].name;
    }

    function getTokenCollectionId(uint256 _tokenId) public view returns (uint256) {
        return metadata[_tokenId].collection;
    }

    function getTokenGemId(uint256 _tokenId) public view returns (uint256) {
        return metadata[_tokenId].gem;
    }

    function getTokenBalance(uint256 _tokenId) public view returns (uint256) {
        return metadata[_tokenId].balance;
    }

    function getCollectionsLength() public view returns (uint256) {
        return collections.length;
    }

    function getGemsLength() public view returns (uint256) {
        return gems.length;
    }

    function totalPrinted() public view returns (uint256) {
        return _tokenCounter;
    }

    function gemsCirculating() public view returns (uint256) {
        return circulatingGems;
    }

    // https://docs.opensea.io/docs/metadata-standards
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return append(collections[metadata[_tokenId].collection].baseURI, toString(_tokenId));
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    function setWstEth(address _wstETH) external onlyOwner {
        require(_wstETH != address(0), "Zero address");
        wstETH = _wstETH;
    }

    function setPayout(address _payout) external onlyOwner {
        require(_payout != address(0), "Zero address");
        payout = _payout;
    }

    function withdrawFees() external onlyOwner {
        (bool success,) = payout.call{value: fees}("");
        require(success, "Transfer failed");
        fees = 0;
    }

    function approveWstEth(address _spender) external onlyOwner {
        require(_spender != address(0), "Zero address");
        IwstETH(wstETH).approve(_spender, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    function append(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
