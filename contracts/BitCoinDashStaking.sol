//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.10;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract ApprovedTokenSpend {}

contract BitCoinDashStaking is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    //events Staking
    event RentingMiner(address indexed user, uint256 amount, uint256 timestamp);
    event FeedMiner(address indexed user, uint256 amount, uint256 timestamp);
    event ClaimReward(address indexed user, uint256 amount, uint256 timestamp);

    address private tokenAddress;
    //wallet address
    address payable public TreasuryWallet;
    address payable public MarketingWallet;
    address payable public CharityWallet;
    address payable public ChimneyWallet;
    address payable public AdminWallet;
    address[10] public LeadersWallet;
    IERC20Upgradeable private BITD_TOKEN;
    IUniswapV2Pair private UNISWAP_PAIR;

    //constant
    uint8[] private REF_BONUSES;
    uint256 private constant DAILY_RETURN = 2;
    uint256 private constant PERCENT_DIVIDER = 100;
    uint256 private constant ONE_PERCENT = 1;
    uint256 private constant TAXRATE = 10;
    uint256 private constant DECIMAL = 10**9;
    uint256 private constant BASE = 10**18;

    uint256 private rentMinerFee;
    uint256 private feedMinerFee;
    uint256 private dailyPercentage;

    //mainnet address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;
    //testnet address: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526;
    address private constant BNB_TO_USD =
        0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526;

    AggregatorV3Interface internal priceFeed;

    mapping(address => User) public users;

    struct Miner {
        uint256 stakestart;
        uint256 minerLastFed; //7 days
        uint256 index;
        uint256 rentFee;
        uint256 dailyPercent;
        bool miningStatus;
        bool expired;
    }

    struct User {
        address userAddress;
        uint256 bonus; //this is gotten from REF_BONUSES
        address referrer;
        uint256 firstDownlineTime;
        uint256 lastDownLineTime;
        uint256 monthlyReferralCount;
        uint256 bonusFromDirectReferral; //this is incremented in value which is .mul by $100 of token
        Miner[] miners;
        uint256[10] levels;
    }

    function initialize(
        address _uniswapPairAddress,
        address _tokenAddress,
        address payable _treasuryWallet,
        address payable _marketingWallet,
        address payable _charityWallet,
        address payable _chimneyWallet,
        address payable _adminWallet,
        address payable[10] calldata _leadersWallet
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        UNISWAP_PAIR = IUniswapV2Pair(_uniswapPairAddress);
        tokenAddress = _tokenAddress;
        TreasuryWallet = _treasuryWallet;
        MarketingWallet = _marketingWallet;
        CharityWallet = _charityWallet;
        ChimneyWallet = _chimneyWallet;
        AdminWallet = _adminWallet;
        LeadersWallet = _leadersWallet;
        REF_BONUSES = [10, 3, 3, 2, 2, 1, 1, 1, 1, 1];
        BITD_TOKEN = IERC20Upgradeable(_tokenAddress);
        priceFeed = AggregatorV3Interface(BNB_TO_USD);
    }

    //user functions
    function rentMiner(address referral, uint256 tokenAmount)
        public
        nonReentrant
    {
        //convert the tokenAmount to the 9 decimal places
        //tokenAmount is coming in as a 1eth 1e18
        //get value of token needed
        uint256 tokenExpected = calculateTokenToDollarsNeeded(rentMinerFee);
        require(tokenAmount >= tokenExpected, "Token amount is not correct");
        require(tokenAmount > 0, "token Amount must be greater than 0");
        require(
            tokenAmount <= BITD_TOKEN.balanceOf(msg.sender),
            "amount not enough"
        );

        //approve the token
        BITD_TOKEN.safeTransferFrom(msg.sender, address(this), tokenAmount);

        //get the user
        User storage user = users[msg.sender];

        Miner memory miner = Miner({
            stakestart: block.timestamp,
            minerLastFed: block.timestamp,
            rentFee: rentMinerFee,
            dailyPercent: dailyPercentage,
            index: 0,
            miningStatus: true,
            expired: false
        });

        //check if the user is a new user
        if (user.userAddress == address(0)) {
            //create a new miner
            //add the miner to the user
            user.userAddress = msg.sender;
            user.bonus = 0;
            user.firstDownlineTime = 0;
            user.referrer = address(0);
            user.lastDownLineTime = 0;
            user.monthlyReferralCount = 0;
            user.bonusFromDirectReferral = 0;
            user.levels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            user.miners.push(miner);
        } else {
            //get the index of the array and increment it
            uint256 minerLength = user.miners.length;
            miner.index = minerLength;
            user.miners.push(miner);
        }

        //upline distribution starts

        //transfer the amount to the
        uint256 onePercentFee = tokenAmount.mul(ONE_PERCENT).div(
            PERCENT_DIVIDER
        );

        //referral bonus is 25% of the token amount
        uint256 referralBonus = onePercentFee.mul(25);
        //distribute the onepercent to those eligible

        BITD_TOKEN.safeTransfer(AdminWallet, onePercentFee.mul(20));
        BITD_TOKEN.safeTransfer(TreasuryWallet, onePercentFee.mul(20));

        BITD_TOKEN.safeTransfer(MarketingWallet, onePercentFee.mul(5));
        BITD_TOKEN.safeTransfer(CharityWallet, onePercentFee.mul(5));

        //leaders wallet length
        uint256 _leadersWalletLength = LeadersWallet.length;
        for (uint256 i = 0; i < _leadersWalletLength; i++) {
            BITD_TOKEN.safeTransfer(LeadersWallet[i], onePercentFee.mul(2));
        }
        emit RentingMiner(msg.sender, tokenAmount, block.timestamp);
        _settleUplineMiners(referral, referralBonus);
    }

    function _settleUplineMiners(address referral, uint256 referralBonus)
        private
    {
        //get the storage users
        User storage user = users[msg.sender];
        //referral address not empty
        if (referral != address(0) && _checkIfUserInSystem(referral)) {
            //set the referral here
            user.referrer = referral;
            //add the bonus to the user referal count
            User storage userReferral = users[referral];
            //check the first and last person reffered
            if (userReferral.firstDownlineTime == 0) {
                userReferral.firstDownlineTime = block.timestamp;
            }
            //performcheck to confirm if the person can claim token
            bool canClaim = _checkIfReferralWithin30days(
                userReferral.firstDownlineTime
            );
            if (canClaim && userReferral.monthlyReferralCount < 10) {
                //increment the monthlyReferalcount here
                userReferral.monthlyReferralCount.add(1);
                userReferral.lastDownLineTime = block.timestamp;
            }
            //add the claim here
            if (canClaim && userReferral.monthlyReferralCount == 10) {
                //claim everything here
                userReferral.bonusFromDirectReferral.add(1);
                userReferral.firstDownlineTime = 0;
                userReferral.lastDownLineTime = 0;
                userReferral.monthlyReferralCount = 0;
            }
            // cannot claim start a new count because everthing has expired
            if (!canClaim) {
                userReferral.firstDownlineTime = block.timestamp;
                userReferral.lastDownLineTime = block.timestamp;
                userReferral.monthlyReferralCount = 1;
            }
        }

        //distribute the referral bonus
        if (user.referrer == address(0) && msg.sender != AdminWallet) {
            user.referrer = AdminWallet;
            address upline = user.referrer;
            for (uint256 i = 0; i < REF_BONUSES.length; i++) {
                if (upline != address(0)) {
                    users[upline].levels[i] = users[upline].levels[i].add(1);
                    upline = users[upline].referrer;
                } else break;
            }
        }

        if (user.referrer != address(0)) {
            address upline = user.referrer;
            for (uint256 i = 0; i < REF_BONUSES.length; i++) {
                if (upline == address(0)) {
                    upline = AdminWallet;
                }
                //multiplying by 4 to round the percent to 100
                //bonus is the token amount they are due
                uint256 amount = referralBonus.mul(REF_BONUSES[i]).mul(4);
                users[upline].bonus = users[upline].bonus.add(amount);
                upline = users[upline].referrer;
            }
        }
    }

    function feedMiner(uint256 _amount, uint256 _minerIndex)
        public
        nonReentrant
    {
        //get the user and the miner you want to feed
        uint256 tokenExpected = calculateTokenToDollarsNeeded(feedMinerFee);
        require(tokenExpected >= _amount, "Token amount is not correct");
        require(_checkIfUserInSystem(msg.sender), "user not in system");
        User storage _user = users[msg.sender];
        //miner to feed
        Miner storage _miner = _user.miners[_minerIndex];
        //get miner and check if we can feed
        require(!_checkIfMinerExpired(_miner), "Miner has expired");
        bool canFeed = _checkMinerCanFeed(_miner.minerLastFed);
        require(canFeed, "can't feed the miner now");
        //we can feed here we need to take the amount
        //and check if we have enough
        require(
            _amount <= BITD_TOKEN.balanceOf(msg.sender),
            "amount not enough"
        );
        BITD_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);

        _miner.miningStatus = true;
        //update the last feed time.
        _miner.minerLastFed = block.timestamp;
        //add the miner back to the feed
        _user.miners[_minerIndex] = _miner;
        emit FeedMiner(msg.sender, _amount, block.timestamp);
    }

    function _checkIfUserInSystem(address _userAddress)
        private
        view
        returns (bool)
    {
        //get the user
        User storage _user = users[_userAddress];
        //check if the user is in the system
        bool isInSystem = _user.userAddress != address(0);
        return isInSystem;
    }

    function _checkIfMinerExpired(Miner memory _miner)
        private
        pure
        returns (bool)
    {
        //check if miner is expired
        return _miner.expired;
    
    }

    function _checkIfReferralWithin30days(uint256 firstReferralTime)
        private
        view
        returns (bool)
    {
        //check if referral is within 30 days
        uint256 refPlus30Days = firstReferralTime.add(30 days);
        if (refPlus30Days > (block.timestamp)) {
            return true;
        } else {
            return false;
        }
    }

    function _checkMinerCanFeed(uint256 _lastFeeding)
        private
        view
        returns (bool)
    {
        //check if feeding is is within 7 days
        uint256 feedingDays = _lastFeeding.add(7 days);
        if (feedingDays > (block.timestamp)) {
            return false;
        } else {
            return true;
        }
    }

    function _isMinerActive(uint256 _lastFeeding) private view returns (bool) {
        //check if feeding is is within 7 days
        uint256 feedingDays = _lastFeeding.add(7 days);
        if (block.timestamp < feedingDays) {
            return true;
        } else {
            return false;
        }
    }

    function _calNumberOfDays(uint256 _lastFeeding) private view returns (uint256) {
        return (block.timestamp - _lastFeeding) / 60 / 60 / 24;
    }

    function claimReward() public nonReentrant {
        //token price 1e26
        require(_checkIfUserInSystem(msg.sender), "user not in system");
        User storage user = users[msg.sender];
        //check bonus
        uint256 _bonus = user.bonus;
        uint256 _directReferral = user.bonusFromDirectReferral;
        //get value from miners
        uint256 minersLength = user.miners.length;
        uint256 totalMinerReward = 0;
        for (uint256 i = 0; i < minersLength; i++) {
            Miner storage miner = user.miners[i];
            uint256 minerStartTime = miner.stakestart;

            uint256 daysOfMinning = _calNumberOfDays(miner.minerLastFed);
            uint256 minerReturnsAmount = ( miner.dailyPercent * miner.rentFee * daysOfMinning ) / 100;
            totalMinerReward += minerReturnsAmount;

            //cal the percentage of the mining
            if (block.timestamp > minerStartTime.add(365 days)) {
                //miner should expire here
                //index i will come back to this later
                user.miners[i].expired = true;
            } else {
                miner.minerLastFed = 0;
                miner.miningStatus = false;
            }
        }
        require(totalMinerReward > 0, "no miner reward to claim");
        uint256 tokenForReward = calculateTokenToDollarsNeeded(
            totalMinerReward
        );
        //each direct referral is == to 100 dolars. bonus is equal to 100 dollars
        uint256 directReferralReward = calculateTokenToDollarsNeeded(
            _directReferral * 100
        );
        //tokenPerDollar is the amount of token per dollar
        uint256 totalToken = tokenForReward + directReferralReward + _bonus;
        //perform the calculation here and know what to transfer

        //taxrate = 10%
        uint256 tax = totalToken.mul(TAXRATE).div(PERCENT_DIVIDER);
        uint256 amountToTransfer = totalToken.mul(90).div(PERCENT_DIVIDER);

        require(
            BITD_TOKEN.balanceOf(address(this)) >= totalToken,
            "not enough liquidity"
        );

        //share the tax to the respective wallet
        //4% = goes to BITD Treasury Wallet (for Liquidity)
        //3% = goes to BITD Marketing Fund Wallet
        //2% = goes to BITD Charity Wallet
        //1% = goes to BITD Chimney Corner (Burn Wallet)

        uint256 treasuryFund = tax.mul(40).div(PERCENT_DIVIDER);
        uint256 marketingFund = tax.mul(30).div(PERCENT_DIVIDER);
        uint256 charityFund = tax.mul(20).div(PERCENT_DIVIDER);
        uint256 chimneyFund = tax.mul(10).div(PERCENT_DIVIDER);

        BITD_TOKEN.safeTransfer(TreasuryWallet, treasuryFund);
        BITD_TOKEN.safeTransfer(MarketingWallet, marketingFund);
        BITD_TOKEN.safeTransfer(CharityWallet, charityFund);
        BITD_TOKEN.safeTransfer(ChimneyWallet, chimneyFund);
        BITD_TOKEN.safeTransfer(msg.sender, amountToTransfer);
        emit ClaimReward(msg.sender, amountToTransfer, block.timestamp);
    }

    function getContractTokenBalance() public view returns (uint256) {
        return BITD_TOKEN.balanceOf(address(this));
    }

    function getUserTokenBalance(address _userAddress)
        public
        view
        returns (uint256)
    {
        return BITD_TOKEN.balanceOf(_userAddress);
    }

    // calculate price based on pair reserves
    function getTokenPrice() public view returns (uint256) {
        (uint256 token, uint256 wbnb, ) = UNISWAP_PAIR.getReserves();
        //get token price in wbnb
        //peform the multiplication bnb / 1e18 / token / 1e9
        uint256 reserves = ((10**18 * (10**9 * wbnb)) / (10**18 * token));

        int256 bnbPrice = _getLatestPriceBNBTOUSD();

        uint256 priceInDollars = reserves * (uint256(bnbPrice));

        return (priceInDollars); //return decimal is in 10**26
    }

    function calculateTokenToDollarsNeeded(uint256 _dollarsAmount)
        public
        view
        returns (uint256 tokens)
    {
        //1e26 because getToken returns value in 10**26
        tokens = (DECIMAL * (_dollarsAmount * 10**26)) / getTokenPrice();
    }

    function _getLatestPriceBNBTOUSD() private view returns (int256) {
        (
            ,
            /*uint80 roundID*/
            int256 price, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,

        ) = priceFeed.latestRoundData();
        return price;
    }

    //admin stuffs

    function setMinerBaseFee(uint256 _fee) public onlyOwner {
        rentMinerFee = _fee;
    }

    function setMinerFeedingFee(uint256 _fee) public onlyOwner {
        feedMinerFee = _fee;
    }

    function setMinerDailyPercentage(uint256 _percentage) public onlyOwner {
        dailyPercentage = _percentage;
    }


    function viewUserEarning() public view returns (uint256, uint256, uint256 ) {
        User memory user = users[msg.sender];
        require(user.userAddress != address(0), "user not in system");
        //lets find the token balance of the user earned
        uint256 _directbonus = user.bonusFromDirectReferral;
        uint256 _bonus = user.bonus;
        //get value from miners
        uint256 minersLength = user.miners.length;
        uint256 totalMinerReward = 0;
        for (uint256 i = 0; i < minersLength; i++) {
            Miner memory miner = user.miners[i];
            uint256 daysOfMinning = _calNumberOfDays(miner.minerLastFed);
            uint256 minerReturnsAmount = ( miner.dailyPercent * miner.rentFee * daysOfMinning ) / 100;
            totalMinerReward += minerReturnsAmount;
        }
        //dollar amount of token
        uint256 tokenForReward = calculateTokenToDollarsNeeded(
            totalMinerReward
        );
        //direct bonus reward
        uint256 bonusReward = calculateTokenToDollarsNeeded(_directbonus * 100);

        
        //tokenForReward => daily tokens
        //bonusReward => direct referral bonus
        //bonus => bonus from referrals
        return (tokenForReward, bonusReward, _bonus);
  
    }

    function viewAnyUserEarning(address _userAddress)
        public
        view
        onlyOwner
        returns (uint256, uint256, uint256 )
    {
        User memory user = users[_userAddress];
        require(user.userAddress != address(0), "user not in system");
        //lets find the token balance of the user earned
        uint256 _directbonus = user.bonusFromDirectReferral;
        uint256 _bonus = user.bonus;
        //get value from miners
        uint256 minersLength = user.miners.length;
        uint256 totalMinerReward = 0;
        for (uint256 i = 0; i < minersLength; i++) {
            Miner memory miner = user.miners[i];
            uint256 daysOfMinning = _calNumberOfDays(miner.minerLastFed);
            uint256 minerReturnsAmount = ( miner.dailyPercent * miner.rentFee * daysOfMinning ) / 100;
            totalMinerReward += minerReturnsAmount;
        }
        //dollar amount of token
        uint256 tokenForReward = calculateTokenToDollarsNeeded(
            totalMinerReward
        );
        //direct bonus reward
        uint256 bonusReward = calculateTokenToDollarsNeeded(_directbonus * 100);

       // uint256 total = tokenForReward + bonusReward + _bonus;
       
        //tokenForReward => daily tokens
        //bonusReward => direct referral bonus
        //bonus => bonus from referrals
        return (tokenForReward, bonusReward, _bonus);
    }

    function viewUserActiveMiners(address _userAddress)
        public
        view
        returns (Miner[] memory)
    {
        User storage user = users[_userAddress];
        require(user.userAddress != address(0), "user not in system");
        uint256 minersLength = user.miners.length;
        uint256 loopIndex = 0;
        uint256 _totalLength = 0;
        for (loopIndex; loopIndex < minersLength; loopIndex++) {
            Miner memory miner = user.miners[loopIndex];
            if (_isMinerActive(miner.minerLastFed)) {
                _totalLength++;
            }
        }
        Miner[] memory activeMiners = new Miner[](_totalLength);
        uint256 _index = 0;
        uint256 i = 0;
        for (i; i < minersLength; i++) {
            Miner memory miner = user.miners[i];
            if (_isMinerActive(miner.minerLastFed)) {
                activeMiners[_index] = miner;
                _index++;
            }
        }
        return activeMiners;
    }

    function getUserDetails(address _address)
        public
        view
        returns (User memory)
    {
        User storage user = users[_address];
        require(user.userAddress != address(0), "user not in system");
        return user;
    }

    function transferToken(address _to, uint256 _amount) public onlyOwner {
        BITD_TOKEN.safeTransfer(_to, _amount);
    }

    function approve(uint256 _amount ) public {
        BITD_TOKEN.safeIncreaseAllowance(address(this), _amount);
    }

    function withdrawTokenFromContract() public onlyOwner {
        uint assetBalance;
        address self = address(this);
        assetBalance = self.balance;
        payable(msg.sender).transfer(assetBalance);
    }

    receive() external payable {}
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
}

//how to get the pair address from uniswap
// address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
// address token0 = 0xCAFE000000000000000000000000000000000000; // change me!
// address token1 = 0xF00D000000000000000000000000000000000000; // change me!

// address pair = address(uint(keccak256(abi.encodePacked(
//   hex'ff',
//   factory,
//   keccak256(abi.encodePacked(token0, token1)),
//   hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'
// ))));

//MAINNET
//Pancake swap factory: 0xca143ce32fe78f1f7019d7d551a6402fc5350c73
//BITNOB token0: 0x638406bba7f0ea45ee2c5ad766f76d9233eb44ae
//WBNB token1: 0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c
//pair address: 0x33cF32D37C1a1209615bfFEaD30edEA8000F9849

//TestNet
//BITNOB token0: 0x57229a8b475ce8e1aee2c0cc81dd3700bcdf5db8
//wBNB token1: 0xae13d989dac2f0debff460ac112a837c89baa7cd
//pair address: 0x86eD77B4e86E6E6835f969563FbA8cE8E5a4fEFa
//factory address: 0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc

//47392942112850 / 1e9 = 47,392.94211285 token
//2343682108450432795 / 1e18 = 2.343682108450432795 bnb

//wbnb / token = 0.00004945213367150238

//49,452,133,671,502.38

//38,200,000,000

//token -> 11180262490499 / 1e9 = 11,180.262490499
//wbnb -> 559229606710777545 /1e18 = 0.559229606710777545 bnb

//result wbnb / token = 0.00005001936288937862 * 1e18 = 50,019,362,889,378.62
