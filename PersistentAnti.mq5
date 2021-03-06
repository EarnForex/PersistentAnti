//+------------------------------------------------------------------+
//|                                               PersistentAnti.mq5 |
//|                             Copyright © 2013-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/PersistentAnti/"
#property version   "1.01"

#property description "Exploits persistent/anti-persistent trend trading."
#property description "Looks up N past bars."
#property description "If at least 66% (empirical) of N bars followed previous bar's direction, we are in persistent mode."
#property description "If at least 66% of N bars went against previous bar's direction, we are in anti-persistent mode."
#property description "If we are in persistent mode - open opposite to previous bar or keep a position which is opposite to previous bar."
#property description "If we are in anti-persistent mode:"
#property description "open in direction of previous bar or keep a position which is in direction of previous bar."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input group "Main"
input int N = 10; // N: How many bars to look up to detect (anti-)persistence?
input double Ratio = 0.66; // Ratio: How big should be the share of (anti-)persistent bars?
input bool Reverse = true; // Reverse: If true, will trade inversely to calculated persistence data.

input group "Money management"
input double Lots = 0.1; // Lots: Basic lot size
input bool MM  = false; // MM: Use money management?
input int Slippage = 100; // Slippage: Tolerated slippage in points
input double MaxPositionSize = 5.0; // MaxPositionSize: Maximum size to use

input group "Miscellaneous"
input string OrderComment = "PersisteneceAnti";

// Main trading objects:
CTrade *Trade;
CPositionInfo PositionInfo;

// Global variables:
ulong LastBars = 0;
bool HaveLongPosition;
bool HaveShortPosition;

void OnInit()
{
    // Initialize the Trade class object.
    Trade = new CTrade;
    Trade.SetDeviationInPoints(Slippage);
}

void OnDeinit(const int reason)
{
    delete Trade;
}

void OnTick()
{
    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!TerminalInfoInteger(TERMINAL_CONNECTED)) || (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)) return;

    int bars = Bars(_Symbol, _Period);

    MqlRates rates[];
    int copied = CopyRates(NULL, 0, 1, N + 1, rates); // Starting from first completed bar. + 1 because need N bars plus one more to compare the last of N to it.
    if (copied <= 0) Print("Error copying price data ", GetLastError());

    int Persistence = 0;
    int Antipersistence = 0;

    // Cycle inside the N-bar range.
    for (int i = 1; i <= N; i++) // i is always pointing at a bar inside N-range.
    {
        // Previous bar was bullish
        if (rates[i - 1].close > rates[i - 1].open)
        {
            // Current bar is bullish
            if (rates[i].close > rates[i].open)
            {
                Persistence++;
            }
            // Current bar is bearish
            else if (rates[i].close < rates[i].open)
            {
                Antipersistence++;
            }
        }
        // Previous bar was bearish
        else if (rates[i - 1].close < rates[i - 1].open)
        {
            // Current bar is bearish
            if (rates[i].close < rates[i].open)
            {
                Persistence++;
            }
            // Current bar is bullish
            else if (rates[i].close > rates[i].open)
            {
                Antipersistence++;
            }
        }
        // NOTE: If previous or current bar is flat, neither persistence or anti-persistence point is scored,
        //       which means that we are more likely to stay out of the market.
    }

    // Check what position is currently open.
    GetPositionStates();

    if (((Persistence > Ratio * N) && (Reverse)) || ((Antipersistence > Ratio * N) && (!Reverse)))
    {
        // If previous bar was bullish, go short. Remember: we are acting on the contrary!
        if (rates[N].close > rates[N].open)
        {
            if (HaveLongPosition) ClosePrevious();
            if (!HaveShortPosition) fSell();
        }
        // If previous bar was bearish, go long.
        else if (rates[N].close < rates[N].open)
        {
            if (HaveShortPosition) ClosePrevious();
            if (!HaveLongPosition) fBuy();
        }
    }
    else if (((Persistence > Ratio * N) && (!Reverse)) || ((Antipersistence > Ratio * N) && (Reverse)))
    {
        // If previous bar was bullish, go long.
        if (rates[N].close > rates[N].open)
        {
            if (HaveShortPosition) ClosePrevious();
            if (!HaveLongPosition) fBuy();
        }
        // If previous bar was bearish, go short.
        else if (rates[N].close < rates[N].open)
        {
            if (HaveLongPosition) ClosePrevious();
            if (!HaveShortPosition) fSell();
        }
    }
    // If no Persistence or Antipersistence is detected, just close current position.
    else if ((HaveLongPosition) || (HaveShortPosition)) ClosePrevious();
}

//+------------------------------------------------------------------+
//| Check what position is currently open.                           |
//+------------------------------------------------------------------+
void GetPositionStates()
{
    // Is there a position on this currency pair?
    if (PositionInfo.Select(_Symbol))
    {
        if (PositionInfo.PositionType() == POSITION_TYPE_BUY)
        {
            HaveLongPosition = true;
            HaveShortPosition = false;
        }
        else if (PositionInfo.PositionType() == POSITION_TYPE_SELL)
        {
            HaveLongPosition = false;
            HaveShortPosition = true;
        }
    }
    else
    {
        HaveLongPosition = false;
        HaveShortPosition = false;
    }
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
void fBuy()
{
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, LotsOptimized(), Ask, 0, 0, OrderComment);
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
void fSell()
{
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, LotsOptimized(), Bid, 0, 0, OrderComment);
}

//+------------------------------------------------------------------+
//| Calculate position size depending on money management.           |
//+------------------------------------------------------------------+
double LotsOptimized()
{
    if (!MM) return Lots;

    double TLots = NormalizeDouble((MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) * 1.5 / 1000)) / 10, 1);

    int NO = 0;
    if (TLots < 0.1) return 0;
    if (TLots > MaxPositionSize) TLots = MaxPositionSize;

    return TLots;
}

//+------------------------------------------------------------------+
//| Close open position.                                             |
//+------------------------------------------------------------------+
void ClosePrevious()
{
    for (int i = 0; i < 10; i++)
    {
        Trade.PositionClose(_Symbol, Slippage);
        if ((Trade.ResultRetcode() != 10008) && (Trade.ResultRetcode() != 10009) && (Trade.ResultRetcode() != 10010))
            Print("Position Close Return Code: ", Trade.ResultRetcodeDescription());
        else return;
    }
}
//+------------------------------------------------------------------+