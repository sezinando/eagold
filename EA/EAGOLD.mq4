//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|      EAGOLD - SellStop level engine defined by user rules       |
//+------------------------------------------------------------------+
#property strict
#property version   "000.901"
#property description "EAGOLD - Only user-defined SellStop level and trailing logic."

input int    MagicNumber      = 1001;
input double Lot              = 0.01;
input double Multiplier       = 1.20;
input int    DigitsLots       = 2;
input double LotIncrement     = 0.01;
input double MaxOpenLot       = 3.00;
input double TakeProfit       = 5.00;
input double BasketProfit     = 4.00;
input double BasketLoss       = 100.00;
input int    SpreadLimit      = 100;
input int    WaitSeconds      = 0;
input int    MiniGrid1        = 250;
input int    SmartGrid1       = 80;
input int    PendingStepTrail = 80;
input int    MaxTrades        = 2000;

color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;
color PanelColor   = clrWhite;

string AvgBuyLineName  = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName  = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName = "EAGOLD_AVG_SELL_TEXT";
string PanelName       = "EAGOLD_EXPOSURE_PANEL";

int      BuySequence    = 0;
int      SellSequence   = 0;
int      CycleNumber    = 0;
datetime LastTradeTime  = 0;
datetime LastCycleStart = 0;

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

bool IsOpenPosition()
{
   return(OrderType() == OP_BUY || OrderType() == OP_SELL);
}

bool IsPendingOrder()
{
   int type = OrderType();
   return(type == OP_BUYLIMIT || type == OP_BUYSTOP || type == OP_SELLLIMIT || type == OP_SELLSTOP);
}

double PointsToPrice(int points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

double NormalizeLot(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0) step = LotIncrement;
   if(step <= 0.0) step = 0.01;
   if(lots < minLot) lots = minLot;
   if(maxLot > 0.0 && lots > maxLot) lots = maxLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;
   lots = MathRound(lots / step) * step;
   if(lots < minLot) lots = minLot;
   if(maxLot > 0.0 && lots > maxLot) lots = maxLot;
   if(MaxOpenLot > 0.0 && lots > MaxOpenLot) lots = MaxOpenLot;
   return(NormalizeDouble(lots, DigitsLots));
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsOpenPosition()) count++;
   }
   return(count);
}

int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && IsPendingOrder()) count++;
   }
   return(count);
}

bool SpreadOK()
{
   if(SpreadLimit <= 0) return(true);
   RefreshRates();
   return(((Ask - Bid) / Point) <= SpreadLimit);
}

bool WaitOK()
{
   if(WaitSeconds <= 0 || LastTradeTime <= 0) return(true);
   return((TimeCurrent() - LastTradeTime) >= WaitSeconds);
}

bool TradeCapacityOK()
{
   if(MaxTrades <= 0) return(true);
   return(CountOpenPositions() + CountPendingOrders() < MaxTrades);
}

bool GetSideAverage(int side, double &averagePrice, double &totalLots)
{
   double weighted = 0.0;
   totalLots = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;
      weighted += OrderOpenPrice() * OrderLots();
      totalLots += OrderLots();
   }
   if(totalLots <= 0.0)
   {
      averagePrice = 0.0;
      return(false);
   }
   averagePrice = NormalizePrice(weighted / totalLots);
   return(true);
}

void GetSideExposure(int side, double &lots, double &pnl, int &count)
{
   lots = 0.0;
   pnl = 0.0;
   count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;
      lots += OrderLots();
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
      count++;
   }
}

double CurrentBasketProfit()
{
   double total = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(total);
}

void DeleteObjectIfExists(string name)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
}

void DrawAverageLine(string lineName, string textName, double averagePrice, color lineColor, string sideText)
{
   if(ObjectFind(0, lineName) < 0) ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, averagePrice);
   ObjectSetDouble(0, lineName, OBJPROP_PRICE1, averagePrice);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);

   datetime t = (Bars > 0 ? Time[0] : TimeCurrent());
   if(ObjectFind(0, textName) < 0) ObjectCreate(0, textName, OBJ_TEXT, 0, t, averagePrice);
   ObjectMove(0, textName, 0, t, averagePrice);
   ObjectSetString(0, textName, OBJPROP_TEXT, sideText + " " + DoubleToString(averagePrice, Digits));
   ObjectSetString(0, textName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, textName, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, textName, OBJPROP_SELECTED, false);
}

void UpdateAveragePriceDisplay()
{
   double buyAvg, buyLots, sellAvg, sellLots;
   bool hasBuy = GetSideAverage(OP_BUY, buyAvg, buyLots);
   bool hasSell = GetSideAverage(OP_SELL, sellAvg, sellLots);

   if(hasBuy) DrawAverageLine(AvgBuyLineName, AvgBuyTextName, buyAvg, AvgBuyColor, "BUY AVG");
   else
   {
      DeleteObjectIfExists(AvgBuyLineName);
      DeleteObjectIfExists(AvgBuyTextName);
   }

   if(hasSell) DrawAverageLine(AvgSellLineName, AvgSellTextName, sellAvg, AvgSellColor, "SELL AVG");
   else
   {
      DeleteObjectIfExists(AvgSellLineName);
      DeleteObjectIfExists(AvgSellTextName);
   }
}

void DeleteAveragePriceDisplay()
{
   DeleteObjectIfExists(AvgBuyLineName);
   DeleteObjectIfExists(AvgSellLineName);
   DeleteObjectIfExists(AvgBuyTextName);
   DeleteObjectIfExists(AvgSellTextName);
}

void CreateOrUpdatePanel()
{
   if(ObjectFind(0, PanelName) < 0) ObjectCreate(0, PanelName, OBJ_LABEL, 0, 0, 0);

   double buyLots, buyPnl, sellLots, sellPnl;
   int buyCount, sellCount;
   GetSideExposure(OP_BUY, buyLots, buyPnl, buyCount);
   GetSideExposure(OP_SELL, sellLots, sellPnl, sellCount);

   double totalLots = buyLots + sellLots;
   double totalPnl = buyPnl + sellPnl;
   int trigger = MiniGrid1 + SmartGrid1;

   string text =
      "EAGOLD v0.901 [ONLY USER SELL ENGINE]\n" +
      "----------------------------------------------\n" +
      "CYCLE: " + IntegerToString(CycleNumber) +
      "   OPEN: " + IntegerToString(buyCount + sellCount) +
      "   PEND: " + IntegerToString(CountPendingOrders()) + "\n" +
      "BUY   " + IntegerToString(buyCount) + " ord  " + DoubleToString(buyLots, 2) + " lot   P/L " + DoubleToString(buyPnl, 2) + "\n" +
      "SELL  " + IntegerToString(sellCount) + " ord  " + DoubleToString(sellLots, 2) + " lot   P/L " + DoubleToString(sellPnl, 2) + "\n" +
      "----------------------------------------------\n" +
      "TOTAL " + IntegerToString(buyCount + sellCount) + " ord  " + DoubleToString(totalLots, 2) + " lot   P/L " + DoubleToString(totalPnl, 2) + "\n" +
      "Balance: " + DoubleToString(AccountBalance(), 2) + "   Equity: " + DoubleToString(AccountEquity(), 2) + "\n" +
      "MiniGrid1: " + IntegerToString(MiniGrid1) +
      "  SmartGrid1: " + IntegerToString(SmartGrid1) +
      "  Trigger: " + IntegerToString(trigger) + "\n" +
      "PendingTrail: " + IntegerToString(PendingStepTrail) +
      "  Basket+: " + DoubleToString(BasketProfit, 2) +
      "  Basket-: " + DoubleToString(BasketLoss, 2);

   ObjectSetString(0, PanelName, OBJPROP_TEXT, text);
   ObjectSetString(0, PanelName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, PanelName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PanelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PanelName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PanelName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, PanelName, OBJPROP_COLOR, PanelColor);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTED, false);
}

void RebuildSequencesFromOpenOrders()
{
   BuySequence = 0;
   SellSequence = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      if(OrderType() == OP_BUY) BuySequence++;
      if(OrderType() == OP_SELL) SellSequence++;
   }
}

bool SendMarketBuy(double lots, string comment)
{
   if(!SpreadOK() || !WaitOK() || !TradeCapacityOK()) return(false);
   RefreshRates();
   lots = NormalizeLot(lots);
   if(lots <= 0.0) return(false);

   double price = NormalizePrice(Ask);
   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_BUY, lots, price, 10, 0, 0, comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - BUY failed. Error=", GetLastError());
      return(false);
   }

   LastTradeTime = TimeCurrent();
   BuySequence++;
   Print("EAGOLD EVENT BUY - Ticket=", ticket, " Lots=", DoubleToString(lots, DigitsLots), " Price=", DoubleToString(price, Digits));
   return(true);
}

bool SendSellStop(double lots, double price, string comment)
{
   if(!SpreadOK() || !TradeCapacityOK()) return(false);
   RefreshRates();
   lots = NormalizeLot(lots);
   price = NormalizePrice(price);

   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(price >= Bid - minDistance) return(false);

   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_SELLSTOP, lots, price, 10, 0, 0, comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - SELL STOP failed. Price=", DoubleToString(price, Digits), " Error=", GetLastError());
      return(false);
   }

   LastTradeTime = TimeCurrent();
   Print("EAGOLD EVENT SELL STOP - Ticket=", ticket, " Lots=", DoubleToString(lots, DigitsLots), " Price=", DoubleToString(price, Digits));
   return(true);
}

bool HasSellStop()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder() && OrderType() == OP_SELLSTOP) return(true);
   }
   return(false);
}

bool StartNewCycle()
{
   if(CountOpenPositions() > 0 || CountPendingOrders() > 0) return(false);
   if(!SpreadOK() || !WaitOK()) return(false);

   BuySequence = 0;
   SellSequence = 0;
   CycleNumber++;
   LastCycleStart = TimeCurrent();

   bool okBuy = SendMarketBuy(Lot, "EAGOLD CYCLE BUY #1");
   if(!okBuy) return(false);

   RefreshRates();
   double initialSellStop = NormalizePrice(Bid - PointsToPrice(PendingStepTrail));
   bool okSellStop = SendSellStop(Lot, initialSellStop, "EAGOLD CYCLE SELL STOP #1");

   if(!okSellStop)
      Print("EAGOLD WARNING - Initial SELL STOP was not created.");

   return(true);
}

bool PositionReachedTakeProfit()
{
   if(TakeProfit <= 0.0) return(false);
   if(OrderType() == OP_BUY) return((Bid - OrderOpenPrice()) >= TakeProfit);
   if(OrderType() == OP_SELL) return((OrderOpenPrice() - Ask) >= TakeProfit);
   return(false);
}

void ProcessIndividualTakeProfits()
{
   if(TakeProfit <= 0.0) return;
   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      if(!PositionReachedTakeProfit()) continue;

      int ticket = OrderTicket();
      int side = OrderType();
      double lots = OrderLots();
      double closePrice = (side == OP_BUY ? Bid : Ask);
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();

      ResetLastError();
      if(OrderClose(ticket, lots, closePrice, 10, clrNONE))
         Print("EAGOLD EVENT TP - Ticket=", ticket, " Side=", side == OP_BUY ? "BUY" : "SELL", " Lots=", DoubleToString(lots, DigitsLots), " P/L=", DoubleToString(pnl, 2));
      else
         Print("EAGOLD ERROR - TP close failed. Ticket=", ticket, " Error=", GetLastError());
   }
}

bool CloseAllEAGOLD()
{
   bool anyAction = false;
   RefreshRates();

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      int ticket = OrderTicket();
      int side = OrderType();
      double lots = OrderLots();
      double price = (side == OP_BUY ? Bid : Ask);

      ResetLastError();
      if(OrderClose(ticket, lots, price, 10, clrNONE)) anyAction = true;
      else Print("EAGOLD ERROR - Basket close failed. Ticket=", ticket, " Error=", GetLastError());
   }

   for(int j = OrdersTotal()-1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsPendingOrder()) continue;

      int pendingTicket = OrderTicket();
      ResetLastError();
      if(OrderDelete(pendingTicket)) anyAction = true;
      else Print("EAGOLD ERROR - Pending delete failed. Ticket=", pendingTicket, " Error=", GetLastError());
   }

   return(anyAction);
}

bool CheckBasketExit()
{
   double basket = CurrentBasketProfit();

   if(BasketProfit > 0.0 && basket >= BasketProfit)
   {
      Print("EAGOLD EVENT BASKET PROFIT - Current=", DoubleToString(basket,2), " Target=", DoubleToString(BasketProfit,2));
      CloseAllEAGOLD();
      BuySequence = 0;
      SellSequence = 0;
      LastTradeTime = TimeCurrent();
      return(true);
   }

   if(BasketLoss > 0.0 && basket <= -BasketLoss)
   {
      Print("EAGOLD EVENT BASKET LOSS - Current=", DoubleToString(basket,2), " Limit=", DoubleToString(BasketLoss,2));
      CloseAllEAGOLD();
      BuySequence = 0;
      SellSequence = 0;
      LastTradeTime = TimeCurrent();
      return(true);
   }

   return(false);
}

double LastSellOpenPrice()
{
   datetime latest = 0;
   double price = 0.0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      if(OrderOpenTime() >= latest)
      {
         latest = OrderOpenTime();
         price = OrderOpenPrice();
      }
   }

   return(price);
}

double NextSellLot()
{
   // Lot sizing is independent of the level logic.
   // The level engine itself uses ONLY MiniGrid1 + SmartGrid1.
   int index = SellSequence + 1;
   if(index <= 1) return(NormalizeLot(Lot));

   double lots = Lot;
   for(int i = 2; i <= index; i++)
      lots *= (Multiplier > 0.0 ? Multiplier : 1.0);

   return(NormalizeLot(lots));
}

void CreateNextSellStop()
{
   // EXACT USER RULE:
   // 1) Reference = last executed SELL.
   // 2) Trigger only after price advances MiniGrid1 + SmartGrid1.
   // 3) New order = SELL STOP below current price by PendingStepTrail.
   // 4) There is only ONE such pending SELL STOP at a time.
   // 5) No MiniGrid2, SmartGrid2, alternating grids, bilateral grid,
   //    opposite-pending logic, market SELL expansion or other grid rules.

   if(HasSellStop()) return;

   double lastSell = LastSellOpenPrice();
   if(lastSell <= 0.0) return;
   if(!SpreadOK() || !WaitOK() || !TradeCapacityOK()) return;

   RefreshRates();
   int triggerPoints = MiniGrid1 + SmartGrid1;
   double advancePoints = (Ask - lastSell) / Point;

   if(advancePoints < triggerPoints) return;

   double lots = NextSellLot();
   double sellStopPrice = NormalizePrice(Bid - PointsToPrice(PendingStepTrail));
   string comment = "EAGOLD NEXT SELL STOP #" + IntegerToString(SellSequence + 1);

   if(SendSellStop(lots, sellStopPrice, comment))
   {
      Print("EAGOLD EVENT NEXT SELL STOP - LastSell=", DoubleToString(lastSell, Digits),
            " AdvancePoints=", DoubleToString(advancePoints, 0),
            " MiniGrid1=", IntegerToString(MiniGrid1),
            " SmartGrid1=", IntegerToString(SmartGrid1),
            " Trigger=", IntegerToString(triggerPoints),
            " Trail=", IntegerToString(PendingStepTrail),
            " Pending=", DoubleToString(sellStopPrice, Digits),
            " Lots=", DoubleToString(lots, DigitsLots));
   }
}

void TrailSellStops()
{
   if(PendingStepTrail <= 0) return;
   RefreshRates();

   double distance = PointsToPrice(PendingStepTrail);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;

      double oldPrice = OrderOpenPrice();
      double desired = NormalizePrice(Bid - distance);

      if(desired > Bid - minDistance)
         desired = NormalizePrice(Bid - minDistance);

      // SELL STOP follows upward price movement only.
      // It never moves downward.
      if(desired <= oldPrice + Point/2.0) continue;

      int ticket = OrderTicket();
      ResetLastError();
      if(OrderModify(ticket, desired, 0, 0, 0, clrNONE))
      {
         Print("EAGOLD EVENT TRAIL SELL STOP - Ticket=", ticket,
               " Old=", DoubleToString(oldPrice, Digits),
               " New=", DoubleToString(desired, Digits),
               " Distance=", IntegerToString(PendingStepTrail));
      }
      else
      {
         Print("EAGOLD ERROR - SellStop trail failed. Ticket=", ticket, " Error=", GetLastError());
      }
   }
}

void ProcessCycle()
{
   ProcessIndividualTakeProfits();
   if(CheckBasketExit()) return;
   RebuildSequencesFromOpenOrders();

   // ONLY the specified SellStop engine is active.
   CreateNextSellStop();
   TrailSellStops();
}

int OnInit()
{
   RebuildSequencesFromOpenOrders();
   CycleNumber = (CountOpenPositions() > 0 || CountPendingOrders() > 0) ? 1 : 0;
   CreateOrUpdatePanel();
   UpdateAveragePriceDisplay();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAveragePriceDisplay();
   DeleteObjectIfExists(PanelName);
}

void OnTick()
{
   if(CountOpenPositions() == 0 && CountPendingOrders() == 0)
      StartNewCycle();
   else
      ProcessCycle();

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
