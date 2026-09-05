//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.600"
#property description "EAGOLD - Trailing opposite orders, SELL mini-grid and basket management."

input int    MagicNumber       = 1001;
input double Lots              = 0.01;
input int    FirstStep         = 150;
input int    TrailingStep      = 100;
input int    MiniGrid1         = 240;
input double K_lot             = 1.10;
input double ProfitTargetPrice = 1.0;
input double BasketTotal       = 5.0;
input int    Slippage          = 10;

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
// BASKET
//====================================================================

// Soma apenas posições abertas. Pendentes não possuem P/L realizado.
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

   // Primeiro fecha posições abertas.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(!IsOpenPosition()) continue;

      int ticket = OrderTicket();
      int type   = OrderType();
      double lots = OrderLots();
      double price = (type == OP_BUY) ? Bid : Ask;

      ResetLastError();

      if(!OrderClose(ticket, lots, price, Slippage, clrNONE))
      {
         Print("EAGOLD ERROR - Basket close failed. Ticket=", ticket,
               " Error=", GetLastError());
      }
   }

   // Depois elimina todas as pendentes restantes.
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
//
// Uma nova BUY só nasce depois que a BUY anterior for efetivamente
// fechada pelo ProfitTarget. A nova BUY é aberta a mercado; FirstStep
// define a distância da nova SELL STOP associada à operação.
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
      return(true);
   }

   if(direction == OP_SELL && (pendingPrice - Ask) < minimumDistance)
   {
      Print("EAGOLD WARNING - BUY STOP could not be created because it is too close. MarketTicket=",
            marketTicket);
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

   return(true);
}

//====================================================================
// TRAILING DAS SELL STOPS
//====================================================================
//
// Enquanto houver BUY aberta, as SELL STOP acompanham o preço para cima
// mantendo TrailingStep. A pendente nunca é recuada.
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

      // A SELL STOP só acompanha para cima.
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
//
// Depois que uma SELL estiver aberta e o preço continuar subindo,
// adiciona uma nova SELL a cada MiniGrid1 pontos a partir da maior
// referência de preço das SELL abertas. O lote da nova ordem é o lote
// anterior multiplicado por K_lot.
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

      // A sucessora só é criada depois do fechamento confirmado.
      // Para BUY, a nova BUY nasce a mercado e FirstStep define sua
      // nova SELL STOP associada.
      if(direction == OP_BUY)
      {
         StartIndependentOperation(OP_BUY, Lots);
      }
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==================================================");
   Print("EAGOLD v0.6.0 INITIALIZED");
   Print("Trailing + SELL MiniGrid + K_lot + Basket");
   Print("FirstStep         = ", FirstStep, " points");
   Print("TrailingStep      = ", TrailingStep, " points");
   Print("MiniGrid1         = ", MiniGrid1, " points");
   Print("K_lot             = ", DoubleToString(K_lot, 2));
   Print("ProfitTargetPrice = ", DoubleToString(ProfitTargetPrice, 2));
   Print("BasketTotal       = ", DoubleToString(BasketTotal, 2));
   Print("MagicNumber       = ", MagicNumber);
   Print("Lots              = ", DoubleToString(Lots, 2));
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("EAGOLD v0.6.0 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   RefreshRates();

   // Basket tem prioridade sobre qualquer nova entrada.
   if(CheckBasket())
      return;

   // Acompanhamento da SELL STOP enquanto o preço sobe.
   TrailSellStops();

   // Gerenciamento do grid SELL depois que uma SELL foi ativada.
   ManageSellMiniGrid();

   // Take individual. A sucessora só é criada após fechamento.
   ManageIndividualTargets();

   // Primeira operação: BUY a mercado + SELL STOP em FirstStep.
   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY, Lots);
}

//+------------------------------------------------------------------+
