//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.603"
#property description "EAGOLD - Trailing, SELL mini-grid, basket, average price, K_lot and exposure panel."

input int    MagicNumber       = 1001;
input double Lots              = 0.01;
input int    FirstStep         = 150;
input int    TrailingStep      = 100;
input int    MiniGrid1         = 240;
input double K_lot             = 1.30;
input double ProfitTargetPrice = 1.0;
input double BasketTotal       = 5.0;
input int    Slippage          = 10;

color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;

string AvgBuyLineName   = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName  = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName   = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName  = "EAGOLD_AVG_SELL_TEXT";
string PanelName        = "EAGOLD_EXPOSURE_PANEL";

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
   return(type == OP_BUYLIMIT || type == OP_BUYSTOP ||
          type == OP_SELLLIMIT || type == OP_SELLSTOP);
}

int CountOpenOrders()
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

double PointsToPrice(int points)
{
   return(points * Point);
}

double NormalizeLot(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0.0) lotStep = 0.01;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   lots = MathRound(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   return(NormalizeDouble(lots, 3));
}

double NextLot(double currentLots)
{
   if(K_lot <= 0.0) return(NormalizeLot(currentLots));
   return(NormalizeLot(currentLots * K_lot));
}

double PositionProfitPrice()
{
   if(OrderType() == OP_BUY)  return(Bid - OrderOpenPrice());
   if(OrderType() == OP_SELL) return(OrderOpenPrice() - Ask);
   return(0.0);
}

bool GetSideAverage(int side, double &averagePrice, double &totalLots)
{
   double weightedPrice = 0.0;
   totalLots = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;
      weightedPrice += OrderOpenPrice() * OrderLots();
      totalLots += OrderLots();
   }
   if(totalLots <= 0.0)
   {
      averagePrice = 0.0;
      return(false);
   }
   averagePrice = NormalizeDouble(weightedPrice / totalLots, Digits);
   return(true);
}

void DeleteObjectIfExists(string name)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
}

void DrawAverageLine(string lineName, string textName, double averagePrice,
                     color lineColor, string sideText)
{
   if(ObjectFind(0, lineName) < 0)
   {
      if(!ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, averagePrice)) return;
   }
   ObjectSetDouble(0, lineName, OBJPROP_PRICE1, averagePrice);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetString(0, lineName, OBJPROP_TOOLTIP,
                   sideText + " " + DoubleToString(averagePrice, Digits));

   datetime textTime = (Bars > 0 ? Time[0] : TimeCurrent());
   if(ObjectFind(0, textName) < 0)
      ObjectCreate(0, textName, OBJ_TEXT, 0, textTime, averagePrice);
   ObjectMove(0, textName, 0, textTime, averagePrice);
   ObjectSetString(0, textName, OBJPROP_TEXT,
                   sideText + " " + DoubleToString(averagePrice, Digits));
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
   bool hasBuy  = GetSideAverage(OP_BUY, buyAvg, buyLots);
   bool hasSell = GetSideAverage(OP_SELL, sellAvg, sellLots);

   if(hasBuy) DrawAverageLine(AvgBuyLineName, AvgBuyTextName, buyAvg, AvgBuyColor, "BUY AVG");
   else { DeleteObjectIfExists(AvgBuyLineName); DeleteObjectIfExists(AvgBuyTextName); }

   if(hasSell) DrawAverageLine(AvgSellLineName, AvgSellTextName, sellAvg, AvgSellColor, "SELL AVG");
   else { DeleteObjectIfExists(AvgSellLineName); DeleteObjectIfExists(AvgSellTextName); }
}

void DeleteAveragePriceDisplay()
{
   DeleteObjectIfExists(AvgBuyLineName);
   DeleteObjectIfExists(AvgSellLineName);
   DeleteObjectIfExists(AvgBuyTextName);
   DeleteObjectIfExists(AvgSellTextName);
}

//====================================================================
// EXPOSIÇÃO E SALDO POR LADO
//====================================================================

void GetSideExposure(int side, double &lots, double &pnl)
{
   lots = 0.0;
   pnl = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != side) continue;
      lots += OrderLots();
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
}

void GetTotalExposure(double &lots, double &pnl)
{
   double buyLots, buyPnl, sellLots, sellPnl;
   GetSideExposure(OP_BUY, buyLots, buyPnl);
   GetSideExposure(OP_SELL, sellLots, sellPnl);
   lots = buyLots + sellLots;
   pnl = buyPnl + sellPnl;
}

void CreateOrUpdatePanel()
{
   if(ObjectFind(0, PanelName) < 0)
   {
      if(!ObjectCreate(0, PanelName, OBJ_LABEL, 0, 0, 0))
      {
         Print("EAGOLD ERROR - Could not create exposure panel. Error=", GetLastError());
         return;
      }
   }

   double buyLots, buyPnl, sellLots, sellPnl, totalLots, totalPnl;
   GetSideExposure(OP_BUY, buyLots, buyPnl);
   GetSideExposure(OP_SELL, sellLots, sellPnl);
   GetTotalExposure(totalLots, totalPnl);

   string text =
      "EAGOLD\n" +
      "--------------------------------\n" +
      "BUY   Exposure: " + DoubleToString(buyLots, 3) + "  P/L: " + DoubleToString(buyPnl, 2) + "\n" +
      "SELL  Exposure: " + DoubleToString(sellLots, 3) + "  P/L: " + DoubleToString(sellPnl, 2) + "\n" +
      "--------------------------------\n" +
      "TOTAL Exposure: " + DoubleToString(totalLots, 3) + "  P/L: " + DoubleToString(totalPnl, 2) + "\n" +
      "Balance: " + DoubleToString(AccountBalance(), 2) +
      "  Equity: " + DoubleToString(AccountEquity(), 2);

   ObjectSetString(0, PanelName, OBJPROP_TEXT, text);
   ObjectSetString(0, PanelName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, PanelName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PanelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PanelName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PanelName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, PanelName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PanelName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, PanelName, OBJPROP_BACK, false);
}

//====================================================================
// BASKET
//====================================================================

double BasketProfit()
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

void CloseBasket()
{
   RefreshRates();
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;
      int ticket = OrderTicket();
      int type = OrderType();
      double lots = OrderLots();
      double price = (type == OP_BUY ? Bid : Ask);
      ResetLastError();
      if(!OrderClose(ticket, lots, price, Slippage, clrNONE))
         Print("EAGOLD ERROR - Basket close failed. Ticket=", ticket, " Error=", GetLastError());
   }
   for(int j = OrdersTotal()-1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsPendingOrder()) continue;
      int ticket2 = OrderTicket();
      ResetLastError();
      if(!OrderDelete(ticket2))
         Print("EAGOLD ERROR - Pending delete failed. Ticket=", ticket2, " Error=", GetLastError());
   }
   UpdateAveragePriceDisplay();
}

bool CheckBasket()
{
   if(BasketTotal <= 0.0) return(false);
   double basket = BasketProfit();
   if(basket >= BasketTotal)
   {
      Print("EAGOLD - Basket target reached. Current=", DoubleToString(basket,2),
            " Target=", DoubleToString(BasketTotal,2));
      CloseBasket();
      return(true);
   }
   return(false);
}

//====================================================================
// OPERAÇÃO
//====================================================================

bool StartIndependentOperation(int direction, double operationLots)
{
   RefreshRates();
   operationLots = NormalizeLot(operationLots);

   int marketType, pendingType;
   double marketPrice, pendingPrice;

   if(direction == OP_BUY)
   {
      marketType = OP_BUY;
      pendingType = OP_SELLSTOP;
      marketPrice = NormalizeDouble(Ask, Digits);
      pendingPrice = NormalizeDouble(marketPrice - PointsToPrice(FirstStep), Digits);
   }
   else if(direction == OP_SELL)
   {
      marketType = OP_SELL;
      pendingType = OP_BUYSTOP;
      marketPrice = NormalizeDouble(Bid, Digits);
      pendingPrice = NormalizeDouble(marketPrice + PointsToPrice(FirstStep), Digits);
   }
   else return(false);

   ResetLastError();
   int marketTicket = OrderSend(Symbol(), marketType, operationLots, marketPrice, Slippage,
                                0, 0, direction == OP_BUY ? "EAGOLD BUY" : "EAGOLD SELL",
                                MagicNumber, 0, clrNONE);
   if(marketTicket < 0)
   {
      Print("EAGOLD ERROR - Market order failed. Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " Error=", GetLastError());
      return(false);
   }

   if(OrderSelect(marketTicket, SELECT_BY_TICKET))
   {
      marketPrice = OrderOpenPrice();
      if(direction == OP_BUY) pendingPrice = NormalizeDouble(marketPrice - PointsToPrice(FirstStep), Digits);
      else pendingPrice = NormalizeDouble(marketPrice + PointsToPrice(FirstStep), Digits);
   }

   RefreshRates();
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(direction == OP_BUY && Bid - pendingPrice < minDistance)
   {
      Print("EAGOLD WARNING - SELL STOP too close. Ticket=", marketTicket);
      UpdateAveragePriceDisplay();
      return(true);
   }
   if(direction == OP_SELL && pendingPrice - Ask < minDistance)
   {
      Print("EAGOLD WARNING - BUY STOP too close. Ticket=", marketTicket);
      UpdateAveragePriceDisplay();
      return(true);
   }

   ResetLastError();
   int pendingTicket = OrderSend(Symbol(), pendingType, operationLots, pendingPrice, Slippage,
                                 0, 0, direction == OP_BUY ? "EAGOLD SELL" : "EAGOLD BUY",
                                 MagicNumber, 0, clrNONE);
   if(pendingTicket < 0)
   {
      Print("EAGOLD ERROR - Opposite pending failed. MarketTicket=", marketTicket,
            " Error=", GetLastError());
   }
   UpdateAveragePriceDisplay();
   return(true);
}

//====================================================================
// TRAILING SELL STOP
//====================================================================

void TrailSellStops()
{
   if(TrailingStep <= 0) return;
   RefreshRates();
   double distance = PointsToPrice(TrailingStep);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;

      double desired = NormalizeDouble(Bid - distance, Digits);
      if(desired > Bid - minDistance) desired = NormalizeDouble(Bid - minDistance, Digits);
      if(desired <= OrderOpenPrice() + Point/2.0) continue;

      int ticket = OrderTicket();
      double oldPrice = OrderOpenPrice();
      ResetLastError();
      if(!OrderModify(ticket, desired, 0, 0, 0, clrNONE))
         Print("EAGOLD ERROR - SELL STOP trailing failed. Ticket=", ticket, " Error=", GetLastError());
      else
         Print("EAGOLD - SELL STOP trailed. Ticket=", ticket,
               " Old=", DoubleToString(oldPrice,Digits),
               " New=", DoubleToString(desired,Digits));
   }
}

//====================================================================
// MINI GRID SELL
//====================================================================

bool GetHighestSell(double &highestPrice, double &highestLot)
{
   bool found = false;
   highestPrice = 0.0;
   highestLot = Lots;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      if(!found || OrderOpenPrice() > highestPrice)
      {
         found = true;
         highestPrice = OrderOpenPrice();
         highestLot = OrderLots();
      }
   }
   return(found);
}

void ManageSellMiniGrid()
{
   if(MiniGrid1 <= 0) return;
   RefreshRates();
   double highestPrice, highestLot;
   if(!GetHighestSell(highestPrice, highestLot)) return;

   double nextLevel = NormalizeDouble(highestPrice + PointsToPrice(MiniGrid1), Digits);
   if(Ask < nextLevel) return;

   double nextLot = NextLot(highestLot);
   double price = NormalizeDouble(Bid, Digits);
   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_SELL, nextLot, price, Slippage, 0, 0,
                          "EAGOLD SELL GRID", MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("EAGOLD ERROR - SELL MiniGrid failed. Level=", DoubleToString(nextLevel,Digits),
            " Lots=", DoubleToString(nextLot,3), " Error=", GetLastError());
      return;
   }
   Print("EAGOLD - SELL MiniGrid opened. Ticket=", ticket,
         " Price=", DoubleToString(price,Digits),
         " Lots=", DoubleToString(nextLot,3));
   UpdateAveragePriceDisplay();
}

//====================================================================
// TAKE INDIVIDUAL
//====================================================================

void ManageIndividualTargets()
{
   RefreshRates();
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || !IsOpenPosition()) continue;

      double profitPrice = PositionProfitPrice();
      if(profitPrice < ProfitTargetPrice) continue;

      int ticket = OrderTicket();
      int direction = OrderType();
      double lots = OrderLots();
      double closePrice = (direction == OP_BUY ? Bid : Ask);
      ResetLastError();
      if(!OrderClose(ticket, lots, closePrice, Slippage, clrNONE))
      {
         Print("EAGOLD ERROR - OrderClose failed. Ticket=", ticket, " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - Individual Take reached. Ticket=", ticket,
            " Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " ProfitPrice=", DoubleToString(profitPrice,2));

      // A nova BUY somente nasce após a BUY anterior ter sido fechada.
      // O lote da sucessora respeita K_lot.
      if(direction == OP_BUY)
      {
         StartIndependentOperation(OP_BUY, NextLot(lots));
      }
      else
      {
         UpdateAveragePriceDisplay();
      }
   }
}

//====================================================================
// INIT / DEINIT / TICK
//====================================================================

int OnInit()
{
   DeleteAveragePriceDisplay();
   DeleteObjectIfExists(PanelName);

   Print("==================================================");
   Print("EAGOLD v0.6.3 INITIALIZED");
   Print("Trailing + SELL MiniGrid + K_lot + Basket + AVG + EXPOSURE");
   Print("FirstStep         = ", FirstStep, " points");
   Print("TrailingStep      = ", TrailingStep, " points");
   Print("MiniGrid1         = ", MiniGrid1, " points");
   Print("K_lot             = ", DoubleToString(K_lot,2));
   Print("ProfitTargetPrice = ", DoubleToString(ProfitTargetPrice,2));
   Print("BasketTotal       = ", DoubleToString(BasketTotal,2));
   Print("MagicNumber       = ", MagicNumber);
   Print("Lots              = ", DoubleToString(Lots,3));
   Print("==================================================");

   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAveragePriceDisplay();
   DeleteObjectIfExists(PanelName);
   Print("EAGOLD v0.6.3 DEINITIALIZED. Reason=", reason);
}

void OnTick()
{
   if(CheckBasket()) return;

   TrailSellStops();
   ManageSellMiniGrid();
   ManageIndividualTargets();
   UpdateAveragePriceDisplay();
   CreateOrUpdatePanel();

   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY, Lots);
}

//+------------------------------------------------------------------+
