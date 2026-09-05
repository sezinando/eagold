//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.601"
#property description "EAGOLD - Trailing, SELL mini-grid, basket and weighted average price display."

input int    MagicNumber       = 1001;
input double Lots              = 0.01;
input int    FirstStep         = 150;
input int    TrailingStep      = 100;
input int    MiniGrid1         = 240;
input double K_lot             = 1.10;
input double ProfitTargetPrice = 1.0;
input double BasketTotal       = 5.0;
input int    Slippage          = 10;

// Cores utilizadas pelo indicador visual de preço médio.
color AvgBuyColor  = clrBlue;
color AvgSellColor = clrRed;

string AvgBuyLineName  = "EAGOLD_AVG_BUY_LINE";
string AvgSellLineName = "EAGOLD_AVG_SELL_LINE";
string AvgBuyTextName  = "EAGOLD_AVG_BUY_TEXT";
string AvgSellTextName = "EAGOLD_AVG_SELL_TEXT";

//====================================================================
// FILTROS DE ORDENS
//====================================================================

bool IsEAGOLDOrder()
{
   if(OrderSymbol() != Symbol()) return(false);
   if(OrderMagicNumber() != MagicNumber) return(false);
   return(true);
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

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(IsOpenPosition()) count++;
   }

   return(count);
}

int CountPendingOrders()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(IsPendingOrder()) count++;
   }

   return(count);
}

//====================================================================
// UTILITÁRIOS
//====================================================================

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

   lots = MathFloor(lots / lotStep + 0.0000001) * lotStep;
   if(lots < minLot) lots = minLot;

   return(NormalizeDouble(lots, 2));
}

double NextLot(double currentLots)
{
   if(K_lot <= 0.0) return(NormalizeLot(currentLots));
   return(NormalizeLot(currentLots * K_lot));
}

double PositionProfitPrice()
{
   if(OrderType() == OP_BUY)
      return(Bid - OrderOpenPrice());

   if(OrderType() == OP_SELL)
      return(OrderOpenPrice() - Ask);

   return(0.0);
}

//====================================================================
// PREÇO MÉDIO POR LADO
//====================================================================
//
// Calcula o preço médio ponderado pelo lote das posições abertas
// EAGOLD do mesmo lado.
//
// BUY AVG  = SUM(PreçoAbertura x Lote) / SUM(Lote)
// SELL AVG = SUM(PreçoAbertura x Lote) / SUM(Lote)
//
// Ordens pendentes não participam do cálculo, pois ainda não possuem
// posição executada.
//====================================================================

bool GetSideAverage(int side, double &averagePrice, double &totalLots)
{
   double weightedPrice = 0.0;
   totalLots = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() != side) continue;

      double lots = OrderLots();
      weightedPrice += OrderOpenPrice() * lots;
      totalLots += lots;
   }

   if(totalLots <= 0.0)
   {
      averagePrice = 0.0;
      return(false);
   }

   averagePrice = NormalizeDouble(weightedPrice / totalLots, Digits);
   return(true);
}

void DeleteAverageObject(string objectName)
{
   if(ObjectFind(0, objectName) >= 0)
      ObjectDelete(0, objectName);
}

void DrawAverageLine(string lineName,
                     string textName,
                     double averagePrice,
                     color lineColor,
                     string sideText)
{
   if(ObjectFind(0, lineName) < 0)
   {
      if(!ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, averagePrice))
      {
         Print("EAGOLD ERROR - Could not create average line. Name=", lineName,
               " Error=", GetLastError());
         return;
      }
   }

   ObjectSetDouble(0, lineName, OBJPROP_PRICE1, averagePrice);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetString(0, lineName, OBJPROP_TOOLTIP,
                   sideText + " AVG " + DoubleToString(averagePrice, Digits));

   // Texto acompanha o preço médio próximo à última barra.
   datetime textTime = TimeCurrent();
   if(Bars > 0)
      textTime = Time[0];

   if(ObjectFind(0, textName) < 0)
   {
      if(!ObjectCreate(0, textName, OBJ_TEXT, 0, textTime, averagePrice))
      {
         Print("EAGOLD ERROR - Could not create average text. Name=", textName,
               " Error=", GetLastError());
         return;
      }
   }

   ObjectMove(0, textName, 0, textTime, averagePrice);
   ObjectSetString(0, textName, OBJPROP_TEXT,
                   sideText + " " + DoubleToString(averagePrice, Digits));
   ObjectSetString(0, textName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, textName, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, textName, OBJPROP_BACK, false);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, textName, OBJPROP_SELECTED, false);
}

void UpdateAveragePriceDisplay()
{
   double buyAverage;
   double buyLots;
   double sellAverage;
   double sellLots;

   bool hasBuy  = GetSideAverage(OP_BUY, buyAverage, buyLots);
   bool hasSell = GetSideAverage(OP_SELL, sellAverage, sellLots);

   if(hasBuy)
   {
      DrawAverageLine(AvgBuyLineName, AvgBuyTextName,
                      buyAverage, AvgBuyColor, "BUY AVG");
   }
   else
   {
      DeleteAverageObject(AvgBuyLineName);
      DeleteAverageObject(AvgBuyTextName);
   }

   if(hasSell)
   {
      DrawAverageLine(AvgSellLineName, AvgSellTextName,
                      sellAverage, AvgSellColor, "SELL AVG");
   }
   else
   {
      DeleteAverageObject(AvgSellLineName);
      DeleteAverageObject(AvgSellTextName);
   }

   ChartRedraw();
}

void DeleteAveragePriceDisplay()
{
   DeleteAverageObject(AvgBuyLineName);
   DeleteAverageObject(AvgSellLineName);
   DeleteAverageObject(AvgBuyTextName);
   DeleteAverageObject(AvgSellTextName);
}

//====================================================================
// BASKET
//====================================================================

double BasketProfit()
{
   double total = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(!IsOpenPosition()) continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return(total);
}

void CloseBasket()
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(!IsOpenPosition()) continue;

      int ticket = OrderTicket();
      int type = OrderType();
      double lots = OrderLots();
      double price = (type == OP_BUY) ? Bid : Ask;

      ResetLastError();

      if(!OrderClose(ticket, lots, price, Slippage, clrNONE))
      {
         Print("EAGOLD ERROR - Basket close failed. Ticket=", ticket,
               " Error=", GetLastError());
      }
   }

   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(!IsPendingOrder()) continue;

      int pendingTicket = OrderTicket();
      ResetLastError();

      if(!OrderDelete(pendingTicket))
      {
         Print("EAGOLD ERROR - Basket pending delete failed. Ticket=",
               pendingTicket, " Error=", GetLastError());
      }
   }

   UpdateAveragePriceDisplay();

   Print("EAGOLD - BASKET CLOSED. BasketProfit reached ",
         DoubleToString(BasketTotal, 2));
}

bool CheckBasket()
{
   if(BasketTotal <= 0.0) return(false);

   double basket = BasketProfit();

   if(basket >= BasketTotal)
   {
      Print("EAGOLD - Basket target reached. Current=",
            DoubleToString(basket, 2),
            " Target=", DoubleToString(BasketTotal, 2));
      CloseBasket();
      return(true);
   }

   return(false);
}

//====================================================================
// OPERAÇÃO INDEPENDENTE
//====================================================================

bool StartIndependentOperation(int direction, double operationLots)
{
   RefreshRates();

   operationLots = NormalizeLot(operationLots);

   int marketType;
   int pendingType;
   double marketPrice;
   double pendingPrice;

   if(direction == OP_BUY)
   {
      marketType   = OP_BUY;
      pendingType  = OP_SELLSTOP;
      marketPrice  = NormalizeDouble(Ask, Digits);
      pendingPrice = NormalizeDouble(marketPrice - PointsToPrice(FirstStep), Digits);
   }
   else if(direction == OP_SELL)
   {
      marketType   = OP_SELL;
      pendingType  = OP_BUYSTOP;
      marketPrice  = NormalizeDouble(Bid, Digits);
      pendingPrice = NormalizeDouble(marketPrice + PointsToPrice(FirstStep), Digits);
   }
   else
      return(false);

   ResetLastError();

   int marketTicket = OrderSend(
      Symbol(), marketType, operationLots, marketPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD BUY" : "EAGOLD SELL",
      MagicNumber, 0, clrNONE
   );

   if(marketTicket < 0)
   {
      Print("EAGOLD ERROR - Market order failed. Direction=",
            direction == OP_BUY ? "BUY" : "SELL",
            " Error=", GetLastError());
      return(false);
   }

   if(OrderSelect(marketTicket, SELECT_BY_TICKET))
   {
      marketPrice = OrderOpenPrice();

      if(direction == OP_BUY)
         pendingPrice = NormalizeDouble(marketPrice - PointsToPrice(FirstStep), Digits);
      else
         pendingPrice = NormalizeDouble(marketPrice + PointsToPrice(FirstStep), Digits);
   }

   RefreshRates();

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(direction == OP_BUY && (Bid - pendingPrice) < minimumDistance)
   {
      Print("EAGOLD WARNING - SELL STOP could not be created because it is too close. MarketTicket=",
            marketTicket);
      UpdateAveragePriceDisplay();
      return(true);
   }

   if(direction == OP_SELL && (pendingPrice - Ask) < minimumDistance)
   {
      Print("EAGOLD WARNING - BUY STOP could not be created because it is too close. MarketTicket=",
            marketTicket);
      UpdateAveragePriceDisplay();
      return(true);
   }

   ResetLastError();

   int pendingTicket = OrderSend(
      Symbol(), pendingType, operationLots, pendingPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD SELL" : "EAGOLD BUY",
      MagicNumber, 0, clrNONE
   );

   if(pendingTicket < 0)
   {
      Print("EAGOLD ERROR - Opposite pending order failed. MarketTicket=",
            marketTicket,
            " Price=", DoubleToString(pendingPrice, Digits),
            " Error=", GetLastError());
      UpdateAveragePriceDisplay();
      return(true);
   }

   Print("EAGOLD - Independent operation started. Direction=",
         direction == OP_BUY ? "BUY" : "SELL",
         " MarketTicket=", marketTicket,
         " Lots=", DoubleToString(operationLots, 2),
         " MarketPrice=", DoubleToString(marketPrice, Digits),
         " PendingTicket=", pendingTicket,
         " PendingPrice=", DoubleToString(pendingPrice, Digits),
         " FirstStep=", FirstStep);

   UpdateAveragePriceDisplay();
   return(true);
}

//====================================================================
// TRAILING DAS SELL STOPS
//====================================================================

void TrailSellStops()
{
   RefreshRates();

   double trailingDistance = PointsToPrice(TrailingStep);
   double minimumDistance  = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(TrailingStep <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() != OP_SELLSTOP) continue;

      double desiredPrice = NormalizeDouble(Bid - trailingDistance, Digits);

      if(desiredPrice > Bid - minimumDistance)
         desiredPrice = NormalizeDouble(Bid - minimumDistance, Digits);

      if(desiredPrice <= OrderOpenPrice() + Point / 2.0)
         continue;

      int ticket = OrderTicket();
      double currentPrice = OrderOpenPrice();

      ResetLastError();

      if(!OrderModify(ticket, desiredPrice, 0, 0, 0, clrNONE))
      {
         Print("EAGOLD ERROR - SELL STOP trailing failed. Ticket=", ticket,
               " Current=", DoubleToString(currentPrice, Digits),
               " Desired=", DoubleToString(desiredPrice, Digits),
               " Error=", GetLastError());
      }
      else
      {
         Print("EAGOLD - SELL STOP trailed. Ticket=", ticket,
               " Old=", DoubleToString(currentPrice, Digits),
               " New=", DoubleToString(desiredPrice, Digits),
               " TrailingStep=", TrailingStep);
      }
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

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() != OP_SELL) continue;

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

   double highestSellPrice;
   double highestSellLot;

   if(!GetHighestSell(highestSellPrice, highestSellLot))
      return;

   double nextLevel = NormalizeDouble(
      highestSellPrice + PointsToPrice(MiniGrid1), Digits
   );

   if(Ask < nextLevel)
      return;

   double nextLot = NextLot(highestSellLot);
   double price   = NormalizeDouble(Bid, Digits);

   ResetLastError();

   int ticket = OrderSend(
      Symbol(), OP_SELL, nextLot, price, Slippage,
      0, 0,
      "EAGOLD SELL GRID",
      MagicNumber, 0, clrNONE
   );

   if(ticket < 0)
   {
      Print("EAGOLD ERROR - SELL MiniGrid order failed. Level=",
            DoubleToString(nextLevel, Digits),
            " Lots=", DoubleToString(nextLot, 2),
            " Error=", GetLastError());
      return;
   }

   Print("EAGOLD - SELL MiniGrid order opened. Ticket=", ticket,
         " Price=", DoubleToString(price, Digits),
         " Lots=", DoubleToString(nextLot, 2),
         " MiniGrid1=", MiniGrid1,
         " K_lot=", DoubleToString(K_lot, 2));

   UpdateAveragePriceDisplay();
}

//====================================================================
// TAKE INDIVIDUAL
//====================================================================

void ManageIndividualTargets()
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(!IsOpenPosition()) continue;

      double profitPrice = PositionProfitPrice();

      if(profitPrice < ProfitTargetPrice)
         continue;

      int ticket = OrderTicket();
      int direction = OrderType();
      double lots = OrderLots();
      double closePrice = (direction == OP_BUY) ? Bid : Ask;

      ResetLastError();

      bool closed = OrderClose(ticket, lots, closePrice, Slippage, clrNONE);

      if(!closed)
      {
         Print("EAGOLD ERROR - OrderClose failed. Ticket=", ticket,
               " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - Individual Take reached. Ticket=", ticket,
            " Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " ProfitPrice=", DoubleToString(profitPrice, 2),
            " Target=", DoubleToString(ProfitTargetPrice, 2));

      if(direction == OP_BUY)
      {
         StartIndependentOperation(OP_BUY, Lots);
      }
      else
      {
         UpdateAveragePriceDisplay();
      }
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   DeleteAveragePriceDisplay();

   Print("==================================================");
   Print("EAGOLD v0.6.1 INITIALIZED");
   Print("Trailing + SELL MiniGrid + K_lot + Basket + AVG PRICE");
   Print("FirstStep         = ", FirstStep, " points");
   Print("TrailingStep      = ", TrailingStep, " points");
   Print("MiniGrid1         = ", MiniGrid1, " points");
   Print("K_lot             = ", DoubleToString(K_lot, 2));
   Print("ProfitTargetPrice = ", DoubleToString(ProfitTargetPrice, 2));
   Print("BasketTotal       = ", DoubleToString(BasketTotal, 2));
   Print("MagicNumber       = ", MagicNumber);
   Print("Lots              = ", DoubleToString(Lots, 2));
   Print("==================================================");

   UpdateAveragePriceDisplay();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAveragePriceDisplay();
   Print("EAGOLD v0.6.1 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   if(CheckBasket())
      return;

   TrailSellStops();
   ManageSellMiniGrid();
   ManageIndividualTargets();
   UpdateAveragePriceDisplay();

   // Primeira operação: somente quando não existe nenhuma ordem EAGOLD.
   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY, Lots);
}

//+------------------------------------------------------------------+
