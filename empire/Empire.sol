// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../libraries/common/DSMath.sol";

import "../interfaces/IEmpireFactory.sol";
import "../interfaces/IEmpirePair.sol";
import "../interfaces/IEmpireRouter.sol";
import "../interfaces/IWBNB.sol";

contract Empire is ERC20, Ownable {
    using DSMath for uint256;
    using Address for address payable;
    using SafeERC20 for IERC20;

    IEmpireFactory public factory;

    uint256 public totalRaised;
    mapping(address => uint256) public contributions;
    address public empireWbnbPair;
    uint256 public end;

    address private immutable WBNB;
    address private immutable empireTeam;
    address private immutable omnisciaTeam;
    address private immutable marketingTeam;

    address private constant REWARD_TREASURY = address(0x3F9B7da1d832199b2dD23670F2623193636f2e88);
    uint256 private constant TEAM_PERCENTAGE = 0.04 ether; // 4% for each team, 2% for marketing
    uint256 private constant BURN_FEE = 0.001 ether; // 0.1% burn on each transfer

    event Contribution(address indexed contributor, uint256 contribution);

    modifier saleActive() {
        require(
            end != 0,
            "Empire::saleActive: Sale hasn't started yet!"
        );
        require(
            block.timestamp <= end,
            "Empire::saleActive: Sale has ended!"
        );
        _;
    }

    modifier onlyPair() {
        require(
            msg.sender == empireWbnbPair,
            "Empire::onlyPair: Insufficient Privileges"
        );
        _;
    }

    constructor(
        address _empireTeam,
        address _omnisciaTeam,
        address _marketingTeam,
        address _wbnb
    ) public ERC20("Empire", "EMPIRE") Ownable() {
        WBNB = _wbnb;
        empireTeam = _empireTeam; //0x5abbd94bb0561938130d83fda22e672110e12528
        omnisciaTeam = _omnisciaTeam; //0x21cfe244fEe27Dcf77c9555A24075fdf0930d656
        marketingTeam = _marketingTeam; //0xA581289F88A2cC9D40ad990F5773c9e6973bc756
    }

    function beginLGE(IEmpireFactory _factory) external onlyOwner() {
        factory = _factory;
        end = block.timestamp + 12 hours;
        PairType pairType =
            address(this) < WBNB
                ? PairType.SweepableToken1
                : PairType.SweepableToken0;
        empireWbnbPair = _factory.createPair(WBNB, address(this), pairType, 0);
    }

    function deposit() public payable saleActive() {
        contributions[msg.sender] += msg.value;
        emit Contribution(msg.sender, msg.value);
    }

    function complete() external onlyOwner() {
        require(
            block.timestamp > end && end != 0,
            "Empire::complete: Sale not complete yet!"
        );
        uint256 _totalRaised = totalRaised = address(this).balance;
        uint256 teamAllocation = _totalRaised.wmul(TEAM_PERCENTAGE); // 4%
        uint256 marketingAllocation = teamAllocation / 2; // 2%

        payable(empireTeam).sendValue(teamAllocation);
        payable(omnisciaTeam).sendValue(teamAllocation);
        payable(marketingTeam).sendValue(marketingAllocation);

        _totalRaised = address(this).balance;

        IWBNB(WBNB).deposit{value: _totalRaised}();

        _mint(empireWbnbPair, 6000 * 1 ether); //  60% / 6000 for LGE

        IERC20(WBNB).safeTransfer(empireWbnbPair, _totalRaised);

        IEmpirePair(empireWbnbPair).mint(address(this));

        _mint(address(this), 250 * 1 ether); // 2.5% / 250 bonus EMPIRE tokens for contributors

        _mint(empireTeam, 1000 * 1 ether); // 10% / 1000 for the EMPIRE team

        _mint(REWARD_TREASURY, 2750 * 1 ether); // 27.5% / 2750 Reserved for future rewards
    }

    function extractFutureRewards(address to, uint256 amount)
        external
        onlyOwner()
    {
        _transfer(REWARD_TREASURY, to, amount);
    }

    function claim() external {
        require(
            contributions[msg.sender] > 0,
            "Empire::claim: No contribution detected!"
        );
        uint256 _totalRaised = totalRaised;
        uint256 _contribution = contributions[msg.sender];

        totalRaised = totalRaised.sub(_contribution);
        delete contributions[msg.sender];

        IERC20(empireWbnbPair).safeTransfer(
            msg.sender,
            IERC20(empireWbnbPair)
                .balanceOf(address(this))
                .mul(_contribution)
                .div(_totalRaised)
        );

        _transfer(
            address(this),
            msg.sender,
            balanceOf(address(this)).mul(_contribution).div(_totalRaised)
        );
    }

    function sweep(uint256 amount, bytes calldata data) external onlyOwner() {
        IEmpirePair(empireWbnbPair).sweep(amount, data);
    }

    function empireSweepCall(uint256 amount, bytes calldata) external onlyPair() {
        IERC20(WBNB).safeTransfer(owner(), amount);
    }

    function unsweep(uint256 amount) external onlyOwner() {
        IERC20(WBNB).approve(empireWbnbPair, amount);
        IEmpirePair(empireWbnbPair).unsweep(amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 burned;
        if (from != empireWbnbPair && to != empireWbnbPair) {
            burned = amount.wmul(BURN_FEE);
            _burn(from, burned);
        }
        _transfer(from, to, amount - burned);
        _approve(from, msg.sender, allowance(from, msg.sender).sub(amount, "ERC20: transfer amount exceeds"));
        return true;
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        if (msg.sender != empireWbnbPair && to != empireWbnbPair) {
            uint256 burned = amount.wmul(BURN_FEE);
            amount -= burned;
            _burn(msg.sender, burned);
        }
        return super.transfer(to, amount);
    }

    receive() external payable {
        deposit();
    }
}
