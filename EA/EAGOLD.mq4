//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.500"
#property description "EAGOLD - Independent operations with trailing opposite orders."

input int    MagicNumber       = 1001;
input double Lots              = 0.01;
input int    FirstStep         = 150;
input double ProfitTargetPrice = 1.0;
input int    Slippage          = 10;

//====================================================================
// CONTADORES
//====================================================================

int CountOpenOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return(count);
}

int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      int type = OrderType();
      if(type == OP_BUYLIMIT || type == OP_BUYSTOP ||
         type == OP_SELLLIMIT || type == OP_SELLSTOP)
         count++;
   }
   return(count);
}

//====================================================================
// CÁLCULOS
//====================================================================

double StepPrice()
{
   return(FirstStep * Point);
}

double OrderProfitPrice()
{
   if(OrderType() == OP_BUY)
      return(Bid - OrderOpenPrice());

   if(OrderType() == OP_SELL)
      return(OrderOpenPrice() - Ask);

   return(0);
}

//====================================================================
// CRIA OPERAÇÃO INDEPENDENTE
//====================================================================

bool StartIndependentOperation(int direction)
{
   RefreshRates();

   int marketType;
   int pendingType;
   double marketPrice;
   double pendingPrice;

   if(direction == OP_BUY)
   {
      marketType   = OP_BUY;
      pendingType  = OP_SELLSTOP;
      marketPrice  = NormalizeDouble(Ask, Digits);
      pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
   }
   else if(direction == OP_SELL)
   {
      marketType   = OP_SELL;
      pendingType  = OP_BUYSTOP;
      marketPrice  = NormalizeDouble(Bid, Digits);
      pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }
   else
      return(false);

   int marketTicket = OrderSend(
      Symbol(), marketType, Lots, marketPrice, Slippage,
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
         pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
      else
         pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }

   RefreshRates();

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(direction == OP_BUY && (Bid - pendingPrice) < minimumDistance)
   {
      Print("EAGOLD ERROR - SELL STOP too close to market. Ticket=", marketTicket);
      return(true);
   }

   if(direction == OP_SELL && (pendingPrice - Ask) < minimumDistance)
   {
      Print("EAGOLD ERROR - BUY STOP too close to market. Ticket=", marketTicket);
      return(true);
   }

   ResetLastError();

   int pendingTicket = OrderSend(
      Symbol(), pendingType, Lots, pendingPrice, Slippage,
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
         " MarketPrice=", DoubleToString(marketPrice, Digits),
         " PendingTicket=", pendingTicket,
         " PendingPrice=", DoubleToString(pendingPrice, Digits),
         " FirstStep=", FirstStep, " points");

   return(true);
}

//====================================================================
// ACOMPANHA AS PENDENTES COM O PREÇO
//====================================================================
//
// Cada posição aberta possui uma ordem oposta associada ao seu nível.
// Enquanto a posição não fechar, a pendente acompanha o movimento
// favorável do preço, preservando FirstStep em relação ao preço atual.
//
// BUY  -> SELL STOP = Bid - FirstStep
// SELL -> BUY STOP  = Ask + FirstStep
//
// A pendente somente é movida para acompanhar o preço. Ela nunca é
// aproximada do mercado além de FirstStep.
//====================================================================

void TrailPendingOrders()
{
   RefreshRates();

   double step = StepPrice();
   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int direction = OrderType();
      int positionTicket = OrderTicket();
      double desiredPrice;

      if(direction == OP_BUY)
         desiredPrice = NormalizeDouble(Bid - step, Digits);
      else
         desiredPrice = NormalizeDouble(Ask + step, Digits);

      // Procura a pendente correspondente à direção/momento.
      int pendingTicket = -1;
      int pendingType = direction == OP_BUY ? OP_SELLSTOP : OP_BUYSTOP;

      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() != MagicNumber) continue;
         if(OrderType() != pendingType) continue;

         pendingTicket = OrderTicket();
         break;
      }

      if(pendingTicket < 0)
         continue;

      if(direction == OP_BUY)
      {
         if(desiredPrice > Bid - minimumDistance)
            desiredPrice = NormalizeDouble(Bid - minimumDistance, Digits);
      }
      else
      {
         if(desiredPrice < Ask + minimumDistance)
            desiredPrice = NormalizeDouble(Ask + minimumDistance, Digits);
      }

      if(!OrderSelect(pendingTicket, SELECT_BY_TICKET))
         continue;

      double currentPrice = OrderOpenPrice();

      // Só modifica se a pendente realmente precisa subir.
      // Para BUY, a SELL STOP acompanha somente para cima.
      // Para SELL, a BUY STOP acompanha somente para baixo.
      bool shouldModify = false;

      if(direction == OP_BUY && desiredPrice > currentPrice + Point/2.0)
         shouldModify = true;

      if(direction == OP_SELL && desiredPrice < currentPrice - Point/2.0)
         shouldModify = true;

      if(!shouldModify)
         continue;

      ResetLastError();

      bool modified = OrderModify(
         pendingTicket,
         desiredPrice,
         0,
         0,
         0,
         clrNONE
      );

      if(!modified)
      {
         Print("EAGOLD ERROR - Pending trail failed. PositionTicket=",
               positionTicket,
               " PendingTicket=", pendingTicket,
               " Error=", GetLastError());
      }
      else
      {
         Print("EAGOLD - Pending order trailed. PositionTicket=",
               positionTicket,
               " PendingTicket=", pendingTicket,
               " NewPrice=", DoubleToString(desiredPrice, Digits));
      }
   }
}

//====================================================================
// GERENCIAMENTO
//====================================================================

void ManageOrders()
{
   RefreshRates();

   // Primeiro acompanha as pendentes.
   TrailPendingOrders();

   // Depois verifica o Take individual de cada posição.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int direction = OrderType();
      double profitPrice = OrderProfitPrice();

      // Take de 1.0 no PREÇO do ativo.
      if(profitPrice < ProfitTargetPrice)
         continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double closePrice = direction == OP_BUY ? Bid : Ask;

      ResetLastError();

      bool closed = OrderClose(
         ticket, lots, closePrice, Slippage, clrNONE
      );

      if(!closed)
      {
         Print("EAGOLD ERROR - OrderClose failed. Ticket=",
               ticket, " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - Order closed by ProfitTarget. Ticket=", ticket,
            " Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " ProfitPrice=", DoubleToString(profitPrice, 2),
            " Target=", DoubleToString(ProfitTargetPrice, 2));

      // Somente depois do fechamento nasce a sucessora na mesma direção.
      StartIndependentOperation(direction);
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==================================================");
   Print("EAGOLD v0.5.0 INITIALIZED");
   Print("Independent operations / trailing pending orders");
   Print("FirstStep         = ", FirstStep, " points");
   Print("ProfitTargetPrice = ", DoubleToString(ProfitTargetPrice, 2));
   Print("MagicNumber       = ", MagicNumber);
   Print("Lots              = ", DoubleToString(Lots, 2));
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("EAGOLD v0.5.0 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   ManageOrders();

   // Primeira operação: somente quando não existe nenhuma ordem EAGOLD.
   // Pendentes existentes nunca geram uma nova posição por conta própria.
   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY);
}

//+------------------------------------------------------------------+
