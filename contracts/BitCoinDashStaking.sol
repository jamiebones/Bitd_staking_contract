//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract BitCoinDashStaking is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{

    address private tokenAddress;
    //wallet address
    address payable public TreasuryWallet;
    address payable public MarketingWallet;
    address payable public CharityWallet;
    address payable public ChimneyWallet;
    address payable public AdminWallet;
    address[10] public LeadersWallet;
    IERC20 private BITD_TOKEN;

    //constant
    uint8[] private  REF_BONUSES;
    uint256 private constant DAILY_RETURN = 2;
    uint256 private constant PERCENT_DIVIDER = 100;
    uint256 private constant ONE_PERCENT = 1;
    uint256 private constant TAXRATE = 10;
    uint256 private constant DECIMAL = 1000000000;

    mapping(address => User) public users;

    struct Miner {
        uint256 stakestart;
        uint256 dailyReward;
        uint256 minerLastFed; //7 days
        bool miningStatus;
        uint256 index;
    }

    struct User {
        address userAddress;
        uint256 bonus;
        address referrer;
        uint256 firstDownlineTime;
        uint256 lastDownLineTime;
        uint256 monthlyReferralCount;
        uint256 bonusFromDirectReferral; //this is incremented in value which is * by $100 of token
        Miner[] miners;
        uint256[10] levels;
    }

    function initialize(address _tokenAddress, 
                        address payable _treasuryWallet,
                        address payable _marketingWallet,
                        address payable _charityWallet,
                        address payable _chimneyWallet,
                        address payable _adminWallet,
                        address payable [10] calldata _leadersWallet) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        
          tokenAddress = _tokenAddress;
        TreasuryWallet = _treasuryWallet;
        MarketingWallet = _marketingWallet;
        CharityWallet = _charityWallet;
        ChimneyWallet = _chimneyWallet;
        AdminWallet = _adminWallet;
        LeadersWallet = _leadersWallet;
        REF_BONUSES = [10, 3, 3, 2, 2, 1, 1, 1, 1, 1];
        BITD_TOKEN = IERC20(_tokenAddress);
    }



    //user functions
    function rentMiner(address referral, uint256 tokenAmount)
        public
        nonReentrant
    {
        require(tokenAmount > 0, "tokenAmount must be greater than 0");
        require(
            tokenAmount <= BITD_TOKEN.balanceOf(msg.sender),
            "amount not enough"
        );
        //approve the token
        BITD_TOKEN.approve(address(this), tokenAmount);
        BITD_TOKEN.transferFrom(msg.sender, address(this), tokenAmount);

        //get the user
        User storage user = users[msg.sender];

        Miner memory miner = Miner({
            stakestart: block.timestamp,
            dailyReward: 7, //7 days profit
            minerLastFed: block.timestamp,
            miningStatus: true,
            index: 0
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
        uint256 onePercentFee = tokenAmount * ONE_PERCENT / PERCENT_DIVIDER;

        //distribute the onepercent to those eligible

        BITD_TOKEN.transfer(AdminWallet, onePercentFee * (20));
        BITD_TOKEN.transfer(TreasuryWallet, onePercentFee *(20));

        BITD_TOKEN.transfer(MarketingWallet, onePercentFee *(5));
        BITD_TOKEN.transfer(CharityWallet, onePercentFee *(5));

        //leaders wallet length
        uint256 _leadersWalletLength = LeadersWallet.length;
        for (uint256 i = 0; i < _leadersWalletLength; i++) {
            BITD_TOKEN.transfer(LeadersWallet[i], onePercentFee * (2));
        }

        //referral address not empty
        if (referral != address(0)) {
            //set the referral here
            user.referrer = referral;
            //add the bonus to the user referal count
            User storage userReferral = users[referral];
            //check the first and last person reffered
            if (userReferral.firstDownlineTime == 0) {
                userReferral.firstDownlineTime = block.timestamp;
            }
            bool canClaim = _checkIfReferralWithin30days(
                userReferral.firstDownlineTime
            );
            if (canClaim && userReferral.monthlyReferralCount < 10) {
                //increment the monthlyReferalcount here
                userReferral.monthlyReferralCount++;
                userReferral.lastDownLineTime = block.timestamp;
            }
            //add the claim here
            if (canClaim && userReferral.monthlyReferralCount == 10) {
                //claim everything here
                userReferral.bonusFromDirectReferral++;
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
                    users[upline].levels[i] = users[upline].levels[i]+(1);
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
                uint256 amount = onePercentFee *(REF_BONUSES[i]);
                users[upline].bonus = users[upline].bonus+(amount);
                upline = users[upline].referrer;
            }
        }
    }


    function _settleUplineMiners(address referral, uint256 onePercentFee) private {
        //get the storage users
        User storage user = users[msg.sender];
         //referral address not empty
        if (referral != address(0)) {
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
                userReferral.monthlyReferralCount++;
                userReferral.lastDownLineTime = block.timestamp;
            }
            //add the claim here
            if (canClaim && userReferral.monthlyReferralCount == 10) {
                //claim everything here
                userReferral.bonusFromDirectReferral++;
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
                    users[upline].levels[i] = users[upline].levels[i]+(1);
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
                uint256 amount = onePercentFee *(REF_BONUSES[i]);
                users[upline].bonus = users[upline].bonus+(amount);
                upline = users[upline].referrer;
            }
        }
    }

    function feedMiner(uint256 _amount, uint256 _minerIndex)
        public
        nonReentrant
    {
        //get the user and the miner you want to feed
        require(!_checkIfUserInSystem(), "user not in system");
        User storage _user = users[msg.sender];
        //miner to feed
        Miner memory _miner = _user.miners[_minerIndex];
        //get miner and check if we can feed
        bool canFeed = _checkMinerCanFeed(_miner.minerLastFed);
        require(canFeed, "can't feed the miner now");
        //we can feed here we need to take the amount
        //and check if we have enough
        require(
            _amount <= BITD_TOKEN.balanceOf(msg.sender),
            "amount not enough"
        );
        //approve the token to be transferred
        BITD_TOKEN.approve(address(this), _amount);
        BITD_TOKEN.transferFrom(msg.sender, address(this), _amount);

        _miner.miningStatus = true;
        _miner.minerLastFed = block.timestamp;
        _miner.dailyReward = _miner.dailyReward+(7);

        //add the miner back to the feed
        _user.miners[_minerIndex] = _miner;
    }

    function _checkIfUserInSystem() private view returns (bool) {
        //get the user
        User storage _user = users[msg.sender];
        //check if the user is in the system
        bool isInSystem = _user.userAddress != address(0);
        return isInSystem;
    }

    function _checkIfReferralWithin30days(uint256 firstReferralTime)
        private
        view
        returns (bool)
    {
        //check if referral is within 30 days
        uint256 refPlus30Days = firstReferralTime+(30 days);
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
        uint256 feedingDays = _lastFeeding+(7 days);
        if (feedingDays > (block.timestamp)) {
            return false;
        } else {
            return true;
        }
    }

    function _updateMinerStatus(
        bool status,
        address _user,
        Miner memory _miner
    ) private {
        //update miner status
        User storage user = users[_user];
        uint256 index = _miner.index;
        _miner.miningStatus = status;
        user.miners[index] = _miner;
    }

    function claimReward(uint256 tokenAmountPerDollar) public nonReentrant {
        require(!_checkIfUserInSystem(), "user not in system");
        User storage user = users[msg.sender];
        //check bonus
        uint256 _bonus = user.bonus;
        //get value from miners
        uint256 minersLength = user.miners.length;
        uint256 totalMinerReward = 0;
        for (uint256 i = 0; i < minersLength; i++) {
            Miner storage miner = user.miners[i];
            uint256 minerStartTime = miner.stakestart;
            totalMinerReward = totalMinerReward+(miner.dailyReward);
            if (block.timestamp > minerStartTime+(365 days)) {
                //miner should be removed destroyed here
                //index i will come back to this later
                // delete user.miners[i];
            } else {
                miner.dailyReward = 0;
                miner.minerLastFed = 0;
                miner.miningStatus = false;
            }
        }
        require(totalMinerReward > 0, "no miner reward to claim");

        //tokenPerDollar is the amount of token per dollar
        uint256 bonusToken = _bonus *(tokenAmountPerDollar);
        uint256 totalTokenByMining = totalMinerReward *(tokenAmountPerDollar);
        uint256 totalToken = bonusToken+(totalTokenByMining);
        //perform the calculation here and know what to transfer

        uint256 tax = totalToken *(TAXRATE) /(PERCENT_DIVIDER);
        uint256 amountToTransfer = totalToken * (90) /(PERCENT_DIVIDER);

        require(
            BITD_TOKEN.balanceOf(address(this)) >= totalToken,
            "not enough liquidity"
        );

        //share the tax to the respective wallet
        //4% = goes to BITD Treasury Wallet (for Liquidity)
        //3% = goes to BITD Marketing Fund Wallet
        //2% = goes to BITD Charity Wallet
        //1% = goes to BITD Chimney Corner (Burn Wallet)

        uint256 treasuryFund = tax *(40) /(PERCENT_DIVIDER);
        uint256 marketingFund = tax *(30) /(PERCENT_DIVIDER);
        uint256 charityFund = tax *(20) /(PERCENT_DIVIDER);
        uint256 chimneyFund = tax *(10) /(PERCENT_DIVIDER);

        BITD_TOKEN.transfer(TreasuryWallet, treasuryFund);
        BITD_TOKEN.transfer(MarketingWallet, marketingFund);
        BITD_TOKEN.transfer(CharityWallet, charityFund);
        BITD_TOKEN.transfer(ChimneyWallet, chimneyFund);
        BITD_TOKEN.transfer(msg.sender, amountToTransfer);

        //10% of the total miner reward distributed

        //if miner stakestart > 365 days then we destroy the miner

        //user only gets 90%

        //check daily reward
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
}

