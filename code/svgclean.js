     
  
function resizeall(name,width) {  
  var textNode = document.getElementsByClassName(name);
  for (i = 0; i < textNode.length; ++i){
    var t = textNode[i];
    var bb = t.getBBox();
    if(t.getAttribute('datapos')) {
      actwidth = width - t.getAttribute('datapos');
      }
    else {
      actwidth = width;
      }
    if (actwidth < bb.width) {
      var widthTransform = actwidth / bb.width;// * parseInt(window.getComputedStyle(t).getPropertyValue('font-size'));
      var heightTransform = 1-((1-widthTransform)/2.5);
//       var newx = bb.x*(1-widthTransform);
//       var newy = 0;//bb.y*(1-widthTransform);
//       t.setAttribute("y",bb.y/widthTransform);
//       t.setAttribute("x",bb.x/heightTransform);
      t.setAttribute("transform",'scale('+widthTransform+' '+heightTransform+')');
      //t.style.fontSize = widthTransform+"px";
      }
    }  
  }

function cleanup() {
  resizeall('resizeme',170);
  resizeall('destinationreftext',28);
  }
  
