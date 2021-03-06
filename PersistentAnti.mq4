//+------------------------------------------------------------------+
//|                                               PersistentAnti.mq4 |
//|                             Copyright © 2013-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/PersistentAnti/"
#property version   "1.01"
#property strict

#property description "Exploits persistent/anti-persistent trend trading."
#property description "Looks up N past bars."
#property description "If at least 66% (empirical) of N bars followed previous bar's direction, we are in persistent mode."
#property description "If at least 66% of N bars went against previous bar's direction, we are in anti-persistent mode."
#property description "If we are in persistent mode - open opposite to previous bar or keep a position which is opposite to previous bar."
#property description "If we are in anti-persistent mode:"
#property description "open in direction of previous bar or keep a position which is in direction of previous bar."

// Main input parameters:
input int N = 10; // N: How many bars to lookup to detect (anti-)persistence?
input double Ratio = 0.66; // Ratio: How big should be the share of (anti-)persistent bars?
input bool Reverse = true; // Reverse: If true, will trade inversely to calculated persistence data.

// Money management:
input double Lots = 0.1; // Lots: Basic lot size
input bool MM  = false; // MM: Use money management?
input int Slippage = 100; // Slippage: Tolerated slippage in points
input double MaxPositionSize = 5.0; // MaxPositionSize: Maximum size to use

// Miscellaneous:
input string OrderCommentary = "PersisteneceAnti";
input int Magic = 2013041812;

// Global variables:
int LastBars = 0;
bool HaveLongPosition;
bool HaveShortPosition;

void OnTick()
{
    if ((!IsTradeAllowed()) || (IsTradeContextBusy()) || (!IsConnected()) || ((!MarketInfo(Symbol(), MODE_TRADEALLOWED)) && (!IsTesting()))) return;

    int Persistence = 0;
    int Antipersistence = 0;

    // Cycle inside the N-bar range.
    for (int i = 1; i <= N; i++) // i is always pointing at a bar inside N-range.
    {
        // Previous bar was bullish
        if (Close[i + 1] > Open[i + 1])
        {
            // Current bar is bullish
            if (Close[i] > Open[i])
            {
                Persistence++;
            }
            // Current bar is bearish
            else if (Close[i] < Open[i])
            {
                Antipersistence++;
            }
        }
        // Previous bar was bearish
        else if (Close[i + 1] < Open[i + 1])
        {
            // Current bar is bearish
            if (Close[i] < Open[i])
            {
                Persistence++;
            }
            // Current bar is bullish
            else if (Close[i] > Open[i])
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
        if (Close[1] > Open[1])
        {
            if (HaveLongPosition) ClosePrevious();
            if (!HaveShortPosition) fSell();
        }
        // If previous bar was bearish, go long.
        else if (Close[1] < Open[1])
        {
            if (HaveShortPosition) ClosePrevious();
            if (!HaveLongPosition) fBuy();
        }
    }
    else if (((Persistence > Ratio * N) && (!Reverse)) || ((Antipersistence > Ratio * N) && (Reverse)))
    {
        // If previous bar was bullish, go long.
        if (Close[1] > Open[1])
        {
            if (HaveShortPosition) ClosePrevious();
            if (!HaveLongPosition) fBuy();
        }
        // If previous bar was bearish, go short.
        else if (Close[1] < Open[1])
        {
            if (HaveLongPosition) ClosePrevious();
            if (!HaveShortPosition) fSell();
        }
    }
    // If no Persistence or Antipersistence is detected, just close current position.
    else if ((HaveLongPosition) || (HaveShortPosition)) ClosePrevious();

    return;
}

//+------------------------------------------------------------------+
//| Check what position is currently open.                           |
//+------------------------------------------------------------------+
void GetPositionStates()
{
    int total = OrdersTotal();
    for (int cnt = 0; cnt < total; cnt++)
    {
        if (OrderSelect(cnt, SELECT_BY_POS, MODE_TRADES) == false) continue;
        if (OrderMagicNumber() != Magic) continue;
        if (OrderSymbol() != Symbol()) continue;

        if (OrderType() == OP_BUY)
        {
            HaveLongPosition = true;
            HaveShortPosition = false;
            return;
        }
        else if (OrderType() == OP_SELL)
        {
            HaveLongPosition = false;
            HaveShortPosition = true;
            return;
        }
    }
    HaveLongPosition = false;
    HaveShortPosition = false;
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
void fBuy()
{
    RefreshRates();
    int result = OrderSend(Symbol(), OP_BUY, LotsOptimized(), Ask, Slippage, 0, 0, OrderCommentary, Magic);
    if (result == -1)
    {
        int e = GetLastError();
        Print("OrderSend Error: ", e);
    }
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
void fSell()
{
    RefreshRates();
    int result = OrderSend(Symbol(), OP_SELL, LotsOptimized(), Bid, Slippage, 0, 0, OrderCommentary, Magic);
    if (result == -1)
    {
        int e = GetLastError();
        Print("OrderSend Error: ", e);
    }
}

//+------------------------------------------------------------------+
//| Calculate position size depending on money management.           |
//+------------------------------------------------------------------+
double LotsOptimized()
{
    if (!MM) return Lots;

    double TLots = NormalizeDouble((MathFloor(AccountBalance() * 1.5 / 1000)) / 10, 1);

    int NO = 0;
    if (TLots < 0.1) return 0;
    if (TLots > MaxPositionSize) TLots = MaxPositionSize;

    return TLots;
}

//+------------------------------------------------------------------+
//| Close previous position.                                         |
//+------------------------------------------------------------------+
void ClosePrevious()
{
    int total = OrdersTotal();
    for (int i = 0; i < total; i++)
    {
        if (OrderSelect(i, SELECT_BY_POS) == false) continue;
        if ((OrderSymbol() == Symbol()) && (OrderMagicNumber() == Magic))
        {
            if (OrderType() == OP_BUY)
            {
                RefreshRates();
                if (!OrderClose(OrderTicket(), OrderLots(), Bid, Slippage))
                {
                    int e = GetLastError();
                    Print("OrderClose Error: ", e);
                }
            }
            else if (OrderType() == OP_SELL)
            {
                RefreshRates();
                if (!OrderClose(OrderTicket(), OrderLots(), Ask, Slippage))
                {
                    int e = GetLastError();
                    Print("OrderClose Error: ", e);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+