pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";


contract Oasis {
    using SafeMath for uint256;

    uint256 constant public ONE_HUNDRED_PERCENTS = 10000;               // 100%
    uint256 constant public DAILY_INTEREST = 300;                       // 3%
    uint256 constant public MARKETING_FEE = 1500;                       // 15%
    uint256 constant public TEAM_FEE = 400;                             // 4%
    uint256 constant public CHARITY_FEE = 100;                             // 1%
    uint256 constant public MAX_DEPOSIT_TIME = 50 days;                 // 150%
    uint256 constant public MAX_USER_DEPOSITS_COUNT = 50;
    uint256 constant public REFBACK_PERCENT = 150;                      // 1.5%
    uint256[] /*constant*/ public referralPercents = [150, 200, 100];   // 1.5%, 2%, 1%

    struct Deposit {
        uint256 time;
        uint256 amount;
    }

    struct User {
        address referrer;
        uint256 firstTime;
        uint256 lastPayment;
        Deposit[] deposits;
    }

    address public marketing = 0xB7f3A6B8bfa63fDF9ce2a2678fEBD969B265dda5;
    address public team = 0x7F4920cd5E104886F97FCDCBaDb9AF79d6FBb83c;
    address public charity = 0x36c92a9Da5256EaA5Ccc355415271b7d2682f32E;
    uint256 public totalDeposits;
    mapping(address => User) public users;

    event InvestorAdded(address investor);
    event ReferrerAdded(address investor, address referrer);
    event DepositAdded(address investor, uint256 depositsCount, uint256 amount);
    event DividendPayed(address investor, uint256 dividend);
    event ReferrerPayed(address investor, address referrer, uint256 amount);
    event FeePayed(address investor, uint256 amount);
    event TotalDepositsChanged(uint256 totalDeposits);
    event BalanceChanged(uint256 balance);
    
    function() public payable {
        User storage user = users[msg.sender];

        // Dividends
        uint256 dividends = dividendsForUser(msg.sender);
        if (dividends > 0) {
            if (dividends > address(this).balance) {
                dividends = address(this).balance;
            }

            msg.sender.transfer(dividends);
            user.lastPayment = now; // solium-disable-line security/no-block-members
            emit DividendPayed(msg.sender, dividends);

            // Cleanup deposits array a bit
            for (uint i = 0; i < user.deposits.length; i++) {
                if (now > user.deposits[i].time.add(MAX_DEPOSIT_TIME)) { // solium-disable-line security/no-block-members
                    user.deposits[i] = user.deposits[user.deposits.length - 1];
                    user.deposits.length -= 1;
                    i -= 1;
                }
            }
        }

        // Deposit
        if (msg.value > 0) {
            if (user.firstTime == 0) {
                user.firstTime = now; // solium-disable-line security/no-block-members
                user.lastPayment = now; // solium-disable-line security/no-block-members
                emit InvestorAdded(msg.sender);
            }

            // Create deposit
            user.deposits.push(Deposit({
                time: now, // solium-disable-line security/no-block-members
                amount: msg.value
            }));
            require(user.deposits.length <= MAX_USER_DEPOSITS_COUNT, "Too many deposits per user");
            emit DepositAdded(msg.sender, user.deposits.length, msg.value);

            // Add to total deposits
            totalDeposits = totalDeposits.add(msg.value);
            emit TotalDepositsChanged(totalDeposits);

            // Add referral if possible
            if (user.referrer == address(0) && msg.data.length == 20) {
                address referrer = bytesToAddress(msg.data);
                if (referrer != address(0) && users[referrer].firstTime > 0 && now >= users[referrer].firstTime.add(1 days)) { // solium-disable-line security/no-block-members
                    user.referrer = referrer;
                    msg.sender.transfer(msg.value.mul(REFBACK_PERCENT).div(ONE_HUNDRED_PERCENTS));
                    emit ReferrerAdded(msg.sender, referrer);
                }
            }

            // Referrers fees
            referrer = users[msg.sender].referrer;
            for (i = 0; referrer != address(0) && i < referralPercents.length; i++) {
                uint256 refAmount = msg.value.mul(referralPercents[i]).div(ONE_HUNDRED_PERCENTS);
                referrer.send(refAmount); // solium-disable-line security/no-send
                emit ReferrerPayed(msg.sender, referrer, refAmount);
                referrer = users[referrer].referrer;
            }

            // Marketing and team fees
            uint256 marketingFee = msg.value.mul(MARKETING_FEE).div(ONE_HUNDRED_PERCENTS);
            uint256 teamFee = msg.value.mul(TEAM_FEE).div(ONE_HUNDRED_PERCENTS);
            uint256 charityFee = msg.value.mul(CHARITY_FEE).div(ONE_HUNDRED_PERCENTS);
            marketing.send(marketingFee); // solium-disable-line security/no-send
            team.send(teamFee); // solium-disable-line security/no-send
            charity.send(charityFee); // solium-disable-line security/no-send
            emit FeePayed(msg.sender, marketingFee.add(teamFee));
        }

        emit BalanceChanged(address(this).balance);
    }

    function depositsCountForUser(address wallet) public view returns(uint256) {
        return users[wallet].deposits.length;
    }

    function depositForUser(address wallet, uint256 index) public view returns(uint256 time, uint256 amount) {
        time = users[wallet].deposits[index].time;
        amount = users[wallet].deposits[index].amount;
    }

    function dividendsForUser(address wallet) public view returns(uint256 dividends) {
        User storage user = users[wallet];
        for (uint i = 0; i < user.deposits.length; i++) {
            uint256 howOld = now.sub(user.deposits[i].time); // solium-disable-line security/no-block-members
            uint256 duration = now.sub(user.lastPayment); // solium-disable-line security/no-block-members
            if (howOld > MAX_DEPOSIT_TIME) {
                uint256 overtime = howOld.sub(MAX_DEPOSIT_TIME);
                if (duration <= overtime) {
                    continue;
                }
                duration = duration.sub(overtime);
            }

            dividends = dividends.add(dividendsForAmountAndTime(
                user.deposits[i].amount, 
                duration // solium-disable-line security/no-block-members
            ));
        }
    }

    function dividendsForAmountAndTime(uint256 amount, uint256 duration) public pure returns(uint256) {
        return amount
            .mul(DAILY_INTEREST).div(ONE_HUNDRED_PERCENTS)
            .mul(duration).div(1 days);
    }

    function bytesToAddress(bytes data) internal pure returns(address addr) {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            addr := mload(add(data, 0x14)) 
        }
    }
}
